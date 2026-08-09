#!/usr/bin/env python3
"""Durable, idempotent local file workflow (SQLite is the source of truth)."""
from __future__ import annotations

import argparse, csv, hashlib, io, json, os, re, shutil, sqlite3, struct, time, unicodedata, uuid, zipfile
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path, PurePosixPath
from typing import Any, Protocol

WORKFLOW_VERSION = "3"
RETRY_DELAYS_MINUTES = (1, 5, 15)
SQLITE_BUSY_RETRIES = (0.025, 0.1, 0.25)
SQLITE_BUSY_TIMEOUT_MS = 2_000
LIFECYCLE = ("inbox", "staging", "validating", "processing", "output_verified", "complete", "archived", "retry_wait", "recovery_required", "quarantine", "security_quarantine")
ALLOWED_TRANSITIONS = {
    "inbox": {"staging", "quarantine", "security_quarantine"},
    "staging": {"validating", "quarantine", "security_quarantine", "recovery_required"},
    "validating": {"processing", "quarantine", "security_quarantine", "recovery_required"},
    "processing": {"output_verified", "retry_wait", "quarantine", "security_quarantine", "recovery_required"},
    "retry_wait": {"processing", "recovery_required", "quarantine", "security_quarantine"},
    "output_verified": {"complete", "recovery_required"},
    "complete": {"archived", "recovery_required"},
}
CHECKPOINTS = ("claimed", "source_verified", "validated", "output_write_started", "output_written", "output_verified", "state_committed", "event_queued")

REASON_CLASSIFICATIONS = {
    "FILE_CORRUPT_CRC_MISMATCH": "corruption",
    "FILE_CORRUPT_TRUNCATED": "corruption",
    "FILE_CORRUPT_CHECKSUM_MISMATCH": "integrity",
    "FILE_FORMAT_MALFORMED": "validation",
    "FILE_VALIDATION_SCHEMA_FAILURE": "validation",
    "PIPELINE_VALIDATION_INTERNAL_ERROR": "internal",
    "PIPELINE_UNKNOWN_VALIDATION_FAILURE": "unknown",
    "FILE_UPLOAD_POLICY_FAILURE": "validation",
    "SECURITY_SCAN_NOT_CLEAN": "security",
}

class ConflictError(RuntimeError): pass

class BinarySeekableReader(Protocol):
    """The binary operations required for in-memory archive inspection."""
    def read(self, size: int = -1) -> bytes: ...
    def seek(self, offset: int, whence: int = 0) -> int: ...
    def tell(self) -> int: ...

@dataclass(frozen=True)
class ScanResult:
    status: str  # clean, infected, error
    engine: str; version: str; reasons: tuple[str, ...] = ()

class FailClosedScanner:
    """Adapter placeholder: unavailable scanning blocks release by design."""
    def scan(self, path: Path) -> ScanResult:
        return ScanResult("error", "unconfigured", "none", ("SCANNER_UNAVAILABLE",))

@dataclass(frozen=True)
class UploadPolicy:
    allowed: dict[str, bytes]
    max_bytes: int = 25_000_000
    max_filename_length: int = 160
    max_archive_files: int = 10_000
    max_archive_bytes: int = 1_000_000_000
    max_archive_entry_bytes: int = 250_000_000
    max_compression_ratio: int = 100
    max_archive_depth: int = 3
    max_archive_path_length: int = 240
    max_archive_path_depth: int = 16
    max_archive_upload_bytes: int = 100_000_000
    max_total_compression_ratio: int = 100
    max_archive_parse_seconds: int = 10
    allow_zip64: bool = False
    malicious_hashes: frozenset[str] = frozenset()

DEFAULT_UPLOAD_POLICY = UploadPolicy({".csv": b"", ".pdf": b"%PDF-", ".png": b"\x89PNG\r\n\x1a\n", ".jpg": b"\xff\xd8\xff", ".jpeg": b"\xff\xd8\xff", ".xlsx": b"PK\x03\x04"})

def now() -> str: return datetime.now(UTC).isoformat(timespec="seconds")
def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for part in iter(lambda: f.read(1024 * 1024), b""): h.update(part)
    return h.hexdigest()
def key(*parts: str) -> str: return hashlib.sha256(":".join(parts).encode()).hexdigest()

@dataclass(frozen=True)
class FileRule:
    name: str; source: str; schedule: str; filename_pattern: str; extensions: tuple[str, ...]; owner: str; sla_minutes: int; destination: str
    min_bytes: int = 1; max_bytes: int = 100_000_000; required_columns: tuple[str, ...] = (); column_types: dict[str, str] | None = None; min_rows: int = 1; max_rows: int = 1_000_000
    @classmethod
    def from_dict(cls, v: dict[str, Any]) -> "FileRule":
        needed = ("name", "source", "schedule", "filename_pattern", "extensions", "owner", "sla_minutes", "destination")
        if any(x not in v for x in needed) or not isinstance(v.get("extensions"), list): raise ValueError("invalid expected-file rule")
        re.compile(str(v["filename_pattern"]))
        return cls(str(v["name"]), str(v["source"]), str(v["schedule"]), str(v["filename_pattern"]), tuple(str(x).lower() for x in v["extensions"]), str(v["owner"]), int(v["sla_minutes"]), str(v["destination"]), int(v.get("min_bytes", 1)), int(v.get("max_bytes", 100_000_000)), tuple(map(str, v.get("required_columns", []))), {str(k): str(x) for k, x in v.get("column_types", {}).items()} or None, int(v.get("min_rows", 1)), int(v.get("max_rows", 1_000_000)))

def load_registry(path: Path) -> list[FileRule]:
    data = json.loads(path.read_text(encoding="utf-8")); entries = data.get("expected_files") if isinstance(data, dict) else None
    if not isinstance(entries, list): raise ValueError("registry must contain expected_files")
    rules = [FileRule.from_dict(x) for x in entries]
    if len({r.name for r in rules}) != len(rules): raise ValueError("rule names must be unique")
    return rules

class Workflow:
    def __init__(self, root: Path, rules: list[FileRule], stable_seconds: int = 30) -> None:
        self.root, self.rules, self.stable_seconds = root.resolve(), rules, stable_seconds
        for state in LIFECYCLE: (self.root / state).mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(self.root / "workflow.sqlite3", timeout=SQLITE_BUSY_TIMEOUT_MS / 1000, isolation_level=None)
        self.db.row_factory = sqlite3.Row
        self.db.executescript("""
        PRAGMA foreign_keys=ON;
        PRAGMA journal_mode=WAL;
        PRAGMA busy_timeout=2000;
        CREATE TABLE IF NOT EXISTS file_records (id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL DEFAULT 'default', source_id TEXT NOT NULL, source_key TEXT NOT NULL, source_event_id TEXT, source_object_version TEXT, source_delivery_id TEXT NOT NULL, checksum_sha256 TEXT NOT NULL, byte_size INTEGER NOT NULL, workflow_version TEXT NOT NULL, rule_name TEXT, state TEXT NOT NULL, current_path TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, quarantine_path TEXT, quarantine_reason TEXT, replaces_file_id TEXT, CHECK(length(checksum_sha256)=64), UNIQUE(tenant_id,source_id,source_delivery_id));
        CREATE TABLE IF NOT EXISTS job_executions (id TEXT PRIMARY KEY, operation_key TEXT NOT NULL UNIQUE, file_id TEXT NOT NULL REFERENCES file_records(id), operation TEXT NOT NULL, status TEXT NOT NULL, attempt_count INTEGER NOT NULL DEFAULT 0, result TEXT, error_code TEXT, error_message TEXT, locked_until TEXT, created_at TEXT NOT NULL, completed_at TEXT, checkpoint TEXT, failure_type TEXT, output_checksum_sha256 TEXT, recovery_required INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS audit_events (id TEXT PRIMARY KEY, file_id TEXT NOT NULL REFERENCES file_records(id), event_type TEXT NOT NULL, state_before TEXT, state_after TEXT, operation_key TEXT, details TEXT NOT NULL, created_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS move_intents (id TEXT PRIMARY KEY, file_id TEXT NOT NULL REFERENCES file_records(id), source_path TEXT NOT NULL, target_path TEXT NOT NULL, checksum_sha256 TEXT NOT NULL, status TEXT NOT NULL, created_at TEXT NOT NULL, completed_at TEXT, temporary_path TEXT);
        CREATE TABLE IF NOT EXISTS result_writes (file_id TEXT NOT NULL REFERENCES file_records(id), business_key TEXT NOT NULL, value TEXT NOT NULL, created_at TEXT NOT NULL, PRIMARY KEY(file_id,business_key));
        CREATE TABLE IF NOT EXISTS outbox_events (id TEXT PRIMARY KEY, event_key TEXT NOT NULL UNIQUE, event_type TEXT NOT NULL, payload TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending', created_at TEXT NOT NULL, published_at TEXT);
        CREATE TABLE IF NOT EXISTS security_scans (file_id TEXT PRIMARY KEY, uploader_id TEXT NOT NULL, source_ip TEXT, original_name TEXT NOT NULL, declared_type TEXT, detected_type TEXT, scan_status TEXT NOT NULL, engine TEXT NOT NULL, engine_version TEXT NOT NULL, reason_codes TEXT NOT NULL, scanned_at TEXT NOT NULL, released_at TEXT);
        CREATE TABLE IF NOT EXISTS evidence_artifacts (id TEXT PRIMARY KEY, file_id TEXT NOT NULL REFERENCES file_records(id), artifact_type TEXT NOT NULL, storage_id TEXT NOT NULL UNIQUE, path TEXT NOT NULL, checksum_sha256 TEXT NOT NULL, access_class TEXT NOT NULL, retention_until TEXT, legal_hold INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, UNIQUE(file_id,artifact_type));
        CREATE TABLE IF NOT EXISTS retention_actions (id TEXT PRIMARY KEY, file_id TEXT NOT NULL REFERENCES file_records(id), action TEXT NOT NULL, requested_by TEXT NOT NULL, approved_by TEXT, executed_by TEXT, created_at TEXT NOT NULL, approved_at TEXT, executed_at TEXT);
        """)
        self._migrate_legacy_identity_schema()
        self.db.execute("CREATE UNIQUE INDEX IF NOT EXISTS unique_source_event ON file_records(tenant_id,source_id,source_event_id) WHERE source_event_id IS NOT NULL")
        self.db.execute("CREATE INDEX IF NOT EXISTS source_version_lookup ON file_records(tenant_id,source_id,source_key,source_object_version)")
        # Small, idempotent local migration for databases created by workflow v2.
        columns = {row[1] for row in self.db.execute("PRAGMA table_info(job_executions)")}
        for column, definition in (("checkpoint", "TEXT"), ("failure_type", "TEXT"), ("output_checksum_sha256", "TEXT"), ("recovery_required", "INTEGER NOT NULL DEFAULT 0")):
            if column not in columns: self.db.execute(f"ALTER TABLE job_executions ADD COLUMN {column} {definition}")
        if "temporary_path" not in {row[1] for row in self.db.execute("PRAGMA table_info(move_intents)")}: self.db.execute("ALTER TABLE move_intents ADD COLUMN temporary_path TEXT")
        file_columns = {row[1] for row in self.db.execute("PRAGMA table_info(file_records)")}
        for column, definition in (("tenant_id", "TEXT NOT NULL DEFAULT 'default'"), ("source_event_id", "TEXT"), ("source_object_version", "TEXT"), ("source_delivery_id", "TEXT"), ("quarantine_path", "TEXT"), ("quarantine_reason", "TEXT"), ("replaces_file_id", "TEXT")):
            if column not in file_columns: self.db.execute(f"ALTER TABLE file_records ADD COLUMN {column} {definition}")
    def close(self) -> None: self.db.close()
    def _migrate_legacy_identity_schema(self) -> None:
        """Rebuild only the legacy identity constraint, preserving every row and FK."""
        schema = self.db.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='file_records'").fetchone()[0]
        if "UNIQUE(source_id,source_key,checksum_sha256)" not in schema.replace(" ", ""):
            return
        self.db.execute("PRAGMA foreign_keys=OFF")
        self.db.execute("PRAGMA legacy_alter_table=ON")
        try:
            self.db.execute("BEGIN EXCLUSIVE")
            self.db.execute("ALTER TABLE file_records RENAME TO file_records_legacy")
            self.db.execute("CREATE TABLE file_records (id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL DEFAULT 'default', source_id TEXT NOT NULL, source_key TEXT NOT NULL, source_event_id TEXT, source_object_version TEXT, source_delivery_id TEXT NOT NULL, checksum_sha256 TEXT NOT NULL, byte_size INTEGER NOT NULL, workflow_version TEXT NOT NULL, rule_name TEXT, state TEXT NOT NULL, current_path TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, quarantine_path TEXT, quarantine_reason TEXT, replaces_file_id TEXT, CHECK(length(checksum_sha256)=64), UNIQUE(tenant_id,source_id,source_delivery_id))")
            legacy_rows = self.db.execute("SELECT * FROM file_records_legacy").fetchall()
            legacy_columns = {column[1] for column in self.db.execute("PRAGMA table_info(file_records_legacy)")}
            for row in legacy_rows:
                values = dict(row)
                tenant_id = values.get("tenant_id") or "default"
                delivery_id = key(tenant_id, values["source_id"], values["source_key"], "version:", values["checksum_sha256"])
                self.db.execute("INSERT INTO file_records VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (values["id"], tenant_id, values["source_id"], values["source_key"], values.get("source_event_id"), values.get("source_object_version"), delivery_id, values["checksum_sha256"], values["byte_size"], values["workflow_version"], values.get("rule_name"), values["state"], values["current_path"], values["created_at"], values["updated_at"], values.get("quarantine_path") if "quarantine_path" in legacy_columns else None, values.get("quarantine_reason") if "quarantine_reason" in legacy_columns else None, values.get("replaces_file_id") if "replaces_file_id" in legacy_columns else None))
            self.db.execute("DROP TABLE file_records_legacy")
            if self.db.execute("PRAGMA foreign_key_check").fetchall():
                raise RuntimeError("legacy identity migration violated foreign keys")
            self.db.execute("COMMIT")
        except Exception:
            self.db.execute("ROLLBACK")
            raise
        finally:
            self.db.execute("PRAGMA legacy_alter_table=OFF")
            self.db.execute("PRAGMA foreign_keys=ON")
    def _begin(self) -> None:
        for delay in (*SQLITE_BUSY_RETRIES, None):
            try:
                self.db.execute("BEGIN IMMEDIATE")
                return
            except sqlite3.OperationalError as exc:
                if "locked" not in str(exc).lower() or delay is None:
                    raise
                time.sleep(delay)
    def _tx(self): return self.db
    def _audit(self, file_id: str, event: str, before: str | None, after: str | None, operation_key: str | None = None, **details: Any) -> None:
        self.db.execute("INSERT INTO audit_events VALUES (?,?,?,?,?,?,?,?)", (str(uuid.uuid4()), file_id, event, before, after, operation_key, json.dumps(details, sort_keys=True), now()))
    def _outbox(self, file_id: str, event_type: str) -> None:
        event_key = key(file_id, WORKFLOW_VERSION, event_type)
        self.db.execute("INSERT OR IGNORE INTO outbox_events VALUES (?,?,?,?,?,?,?)", (str(uuid.uuid4()), event_key, event_type, json.dumps({"file_id": file_id}), "pending", now(), None))
    def matching_rule(self, path: Path) -> FileRule | None:
        found = [r for r in self.rules if re.fullmatch(r.filename_pattern, path.name)]
        return found[0] if len(found) == 1 else None
    def validate(self, path: Path, rule: FileRule) -> None:
        if path.suffix.lower() not in rule.extensions: raise ValueError("unsupported extension")
        if not rule.min_bytes <= path.stat().st_size <= rule.max_bytes: raise ValueError("file size outside threshold")
        if path.suffix.lower() != ".csv": return
        with path.open(encoding="utf-8-sig", newline="") as f:
            rows = csv.DictReader(f)
            if not rows.fieldnames or not set(rule.required_columns).issubset(rows.fieldnames): raise ValueError("missing required columns")
            count = 0
            for row in rows:
                count += 1
                for column, kind in (rule.column_types or {}).items():
                    try:
                        if kind == "int": int(row[column])
                        elif kind == "float": float(row[column])
                        elif kind == "str" and row[column]: pass
                        else: raise ValueError
                    except (KeyError, ValueError) as exc: raise ValueError(f"invalid {kind} value in {column}") from exc
            if not rule.min_rows <= count <= rule.max_rows: raise ValueError("row count outside threshold")
    def register_file(self, path: Path, source_id: str, source_key: str, rule: FileRule | None, *, tenant_id: str = "default", source_event_id: str | None = None, source_object_version: str | None = None, source_delivery_id: str | None = None) -> sqlite3.Row:
        """Register a receipt without globally deduplicating identical content."""
        checksum, size = digest(path), path.stat().st_size
        delivery_marker = f"event:{source_event_id}" if source_event_id else f"version:{source_object_version or ''}"
        delivery_id = source_delivery_id or key(tenant_id, source_id, source_key, delivery_marker, checksum)
        self._begin()
        try:
            if source_event_id:
                prior = self.db.execute("SELECT * FROM file_records WHERE tenant_id=? AND source_id=? AND source_event_id=?", (tenant_id, source_id, source_event_id)).fetchone()
                if prior:
                    if prior["checksum_sha256"] != checksum: raise ConflictError("FILE_SOURCE_EVENT_CONTENT_CONFLICT")
                    self.db.execute("COMMIT"); return prior
            if source_object_version:
                prior = self.db.execute("SELECT * FROM file_records WHERE tenant_id=? AND source_id=? AND source_key=? AND source_object_version=?", (tenant_id, source_id, source_key, source_object_version)).fetchone()
                if prior and prior["checksum_sha256"] != checksum: raise ConflictError("FILE_SOURCE_VERSION_CONTENT_CONFLICT")
            row = self.db.execute("SELECT * FROM file_records WHERE tenant_id=? AND source_id=? AND source_delivery_id=?", (tenant_id, source_id, delivery_id)).fetchone()
            if row:
                self.db.execute("COMMIT"); return row
            file_id = str(uuid.uuid4())
            self.db.execute("INSERT INTO file_records (id,tenant_id,source_id,source_key,source_event_id,source_object_version,source_delivery_id,checksum_sha256,byte_size,workflow_version,rule_name,state,current_path,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (file_id, tenant_id, source_id, source_key, source_event_id, source_object_version, delivery_id, checksum, size, WORKFLOW_VERSION, rule.name if rule else None, "inbox", str(path), now(), now()))
            row = self.db.execute("SELECT * FROM file_records WHERE id=?", (file_id,)).fetchone(); self.db.execute("COMMIT"); return row
        except Exception: self.db.execute("ROLLBACK"); raise
    def claim_job(self, file_id: str, operation: str, lease_minutes: int = 10) -> sqlite3.Row:
        op_key = key(file_id, WORKFLOW_VERSION, operation); lease = (datetime.now(UTC) + timedelta(minutes=lease_minutes)).isoformat(timespec="seconds")
        self._begin()
        try:
            inserted = self.db.execute("INSERT OR IGNORE INTO job_executions (id,operation_key,file_id,operation,status,attempt_count,locked_until,created_at,checkpoint) VALUES (?,?,?,?,?,?,?,?,?)", (str(uuid.uuid4()), op_key, file_id, operation, "running", 1, lease, now(), "claimed")).rowcount == 1
            job = self.db.execute("SELECT *, ? AS claimed FROM job_executions WHERE operation_key=?", (int(inserted), op_key)).fetchone()
            if job["status"] in ("failed", "running") and job["locked_until"] and job["locked_until"] < now():
                self.db.execute("UPDATE job_executions SET status='running',attempt_count=attempt_count+1,locked_until=?,error_code=NULL,error_message=NULL WHERE operation_key=?", (lease, op_key)); job = self.db.execute("SELECT *, 1 AS claimed FROM job_executions WHERE operation_key=?", (op_key,)).fetchone()
            self.db.execute("COMMIT"); return job
        except Exception: self.db.execute("ROLLBACK"); raise
    def checkpoint(self, job: sqlite3.Row, checkpoint: str, output_checksum: str | None = None) -> None:
        if checkpoint not in CHECKPOINTS: raise ValueError("unknown checkpoint")
        self._begin()
        try:
            self.db.execute("UPDATE job_executions SET checkpoint=?,output_checksum_sha256=COALESCE(?,output_checksum_sha256) WHERE id=? AND status='running'", (checkpoint, output_checksum, job["id"])); self._audit(job["file_id"], "job.checkpoint", None, None, job["operation_key"], checkpoint=checkpoint); self.db.execute("COMMIT")
        except Exception: self.db.execute("ROLLBACK"); raise
    def transition(self, file_id: str, expected: str, target: str, operation_key: str | None = None) -> bool:
        if target not in ALLOWED_TRANSITIONS.get(expected, set()):
            raise ValueError(f"invalid state transition: {expected} -> {target}")
        self._begin()
        try:
            changed = self.db.execute("UPDATE file_records SET state=?,updated_at=? WHERE id=? AND state=?", (target, now(), file_id, expected)).rowcount == 1
            if changed:
                self._audit(file_id, "file.transition", expected, target, operation_key)
                if target in ("complete", "quarantine"): self._outbox(file_id, f"file.{target}")
            self.db.execute("COMMIT"); return changed
        except Exception: self.db.execute("ROLLBACK"); raise
    def move_with_intent(self, file_id: str, source: Path, target: Path) -> Path:
        checksum = digest(source); intent = str(uuid.uuid4()); target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.parent / ".partial" / intent
        self._begin()
        try:
            self.db.execute("INSERT INTO move_intents (id,file_id,source_path,target_path,checksum_sha256,status,created_at,completed_at,temporary_path) VALUES (?,?,?,?,?,?,?,?,?)", (intent, file_id, str(source), str(target), checksum, "pending", now(), None, str(temporary))); self.db.execute("COMMIT")
        except Exception: self.db.execute("ROLLBACK"); raise
        if target.exists():
            if digest(target) != checksum: raise FileExistsError(f"refusing to overwrite {target}")
        else:
            temporary.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(source, temporary)
            if digest(temporary) != checksum: raise IOError("copy checksum mismatch")
            os.replace(temporary, target); source.unlink()  # only after verified copy and promotion
        if digest(target) != checksum: raise IOError("destination checksum mismatch")
        self._begin(); self.db.execute("UPDATE move_intents SET status='complete',completed_at=? WHERE id=?", (now(), intent)); self.db.execute("UPDATE file_records SET current_path=?,updated_at=? WHERE id=?", (str(target), now(), file_id)); self.db.execute("COMMIT"); return target
    def write_result(self, file_id: str, business_key: str, value: dict[str, Any]) -> None:
        self.db.execute("INSERT OR IGNORE INTO result_writes VALUES (?,?,?,?)", (file_id, business_key, json.dumps(value, sort_keys=True), now()))
    def complete_job(self, job: sqlite3.Row, result: dict[str, Any]) -> None:
        self._begin()
        try:
            self.db.execute("UPDATE job_executions SET status='succeeded',result=?,completed_at=?,locked_until=NULL WHERE id=?", (json.dumps(result, sort_keys=True), now(), job["id"])); self._audit(job["file_id"], "job.succeeded", None, None, job["operation_key"], result=result); self.db.execute("COMMIT")
        except Exception: self.db.execute("ROLLBACK"); raise
    def commit_completion(self, job: sqlite3.Row, result: dict[str, Any]) -> bool:
        """Commit final state, successful execution, audit, and outbox together."""
        self._begin()
        try:
            changed = self.db.execute("UPDATE file_records SET state='complete',updated_at=? WHERE id=? AND state='output_verified'", (now(), job["file_id"])).rowcount == 1
            if changed:
                self.db.execute("UPDATE job_executions SET status='succeeded',result=?,checkpoint='event_queued',completed_at=?,locked_until=NULL WHERE id=? AND status='running'", (json.dumps(result, sort_keys=True), now(), job["id"])); self._audit(job["file_id"], "file.completed", "output_verified", "complete", job["operation_key"]); self._outbox(job["file_id"], "file.completed")
            self.db.execute("COMMIT"); return changed
        except Exception: self.db.execute("ROLLBACK"); raise
    def fail_job(self, job: sqlite3.Row, error: Exception) -> None:
        self._begin(); self.db.execute("UPDATE job_executions SET status='failed',error_code=?,error_message=?,locked_until=? WHERE id=?", (type(error).__name__, str(error), now(), job["id"])); self._audit(job["file_id"], "job.failed", None, None, job["operation_key"], error=type(error).__name__); self._outbox(job["file_id"], "file.failed"); self.db.execute("COMMIT")
    def require_recovery(self, job: sqlite3.Row, error: Exception) -> None:
        self._begin()
        try:
            self.db.execute("UPDATE job_executions SET status='recovery_required',failure_type='unknown',recovery_required=1,error_code=?,error_message=?,locked_until=NULL WHERE id=?", (type(error).__name__, str(error), job["id"])); self.db.execute("UPDATE file_records SET state='recovery_required',updated_at=? WHERE id=? AND state NOT IN ('complete','archived','quarantine','security_quarantine')", (now(), job["file_id"])); self._audit(job["file_id"], "job.recovery_required", None, "recovery_required", job["operation_key"], error=type(error).__name__); self._outbox(job["file_id"], "file.recovery_required"); self.db.execute("COMMIT")
        except Exception: self.db.execute("ROLLBACK"); raise
    def quarantine_file(self, record: sqlite3.Row, job: sqlite3.Row, error: Exception, primary_reason: str = "PIPELINE_UNKNOWN_VALIDATION_FAILURE", stage: str = "validation", security: bool = False, secondary_reasons: tuple[str, ...] = ()) -> Path:
        """Copy immutable evidence, then atomically quarantine one file version."""
        classification = REASON_CLASSIFICATIONS.get(primary_reason, "security" if security else None)
        if classification is None: raise ValueError("invalid primary quarantine reason")
        record = self.db.execute("SELECT * FROM file_records WHERE id=?", (record["id"],)).fetchone()
        source = Path(record["current_path"])
        state = "security_quarantine" if security else "quarantine"
        root = "security_quarantine" if security else "quarantine"
        evidence_id = str(uuid.uuid4()); folder = self.root / root / evidence_id; original = folder / "original.bin"
        folder.mkdir(parents=True, exist_ok=True)
        if source.exists() and not original.exists(): shutil.copy2(source, original)
        if not original.exists() or digest(original) != record["checksum_sha256"]: raise IOError("cannot establish immutable quarantine evidence")
        os.chmod(original, 0o444)
        manifest = {"file_id": record["id"], "evidence_id": evidence_id, "source": record["source_id"], "original_name": source.name, "sha256": record["checksum_sha256"], "detected_at": now(), "pipeline_stage": stage, "primary_reason_code": primary_reason, "secondary_reason_codes": secondary_reasons, "attempt_count": job["attempt_count"], "workflow_version": WORKFLOW_VERSION}
        artifacts: list[tuple[str, Path]] = [("original", original)]
        for name, payload in (("manifest.json", manifest), ("validation-report.json", {"classification": classification, "stage": stage, "primary_reason_code": primary_reason, "secondary_reason_codes": secondary_reasons, "error_code": type(error).__name__})):
            temporary = folder / f".{name}.tmp"; temporary.write_text(json.dumps(payload, sort_keys=True, indent=2) + "\n", encoding="utf-8"); artifact = folder / name; os.replace(temporary, artifact); os.chmod(artifact, 0o444)
            artifacts.append((name.removesuffix(".json"), artifact))
        self._begin()
        try:
            before = self.db.execute("SELECT state FROM file_records WHERE id=?", (record["id"],)).fetchone()[0]
            changed = self.db.execute("UPDATE file_records SET state=?,current_path=?,quarantine_path=?,quarantine_reason=?,updated_at=? WHERE id=? AND state IN ('inbox','staging','validating','processing','retry_wait','recovery_required')", (state, str(original), str(original), primary_reason, now(), record["id"])).rowcount
            if changed:
                self.db.execute("UPDATE job_executions SET status='failed',checkpoint='quarantined',failure_type='permanent',error_code=?,error_message=?,completed_at=?,locked_until=NULL WHERE id=? AND status IN ('running','recovery_required')", (primary_reason, type(error).__name__, now(), job["id"]));
                for artifact_type, artifact in artifacts:
                    self.db.execute("INSERT INTO evidence_artifacts VALUES (?,?,?,?,?,?,?,?,?,?)", (str(uuid.uuid4()), record["id"], artifact_type, f"evidence/{evidence_id}/{artifact_type}", str(artifact), digest(artifact), "security-restricted" if security else "quarantine-restricted", None, 0, now()))
                self._audit(record["id"], "evidence.captured", before, state, job["operation_key"], evidence_id=evidence_id, primary_reason_code=primary_reason)
                self._audit(record["id"], "file.quarantined", before, state, job["operation_key"], classification=classification, primary_reason_code=primary_reason, secondary_reason_codes=secondary_reasons, stage=stage); self._outbox(record["id"], "file.quarantined")
            self.db.execute("COMMIT"); return original
        except Exception: self.db.execute("ROLLBACK"); raise
    def quarantine_metrics(self) -> dict[str, int]:
        return {"count": self.db.execute("SELECT count(*) FROM file_records WHERE state='quarantine'").fetchone()[0], "repeated_sources": self.db.execute("SELECT count(*) FROM (SELECT source_id FROM file_records WHERE state='quarantine' GROUP BY source_id HAVING count(*) > 3)").fetchone()[0]}
    def security_metrics(self) -> dict[str, int]:
        return {"scans": self.db.execute("SELECT count(*) FROM security_scans").fetchone()[0], "blocked": self.db.execute("SELECT count(*) FROM security_scans WHERE scan_status != 'clean'").fetchone()[0], "scan_errors": self.db.execute("SELECT count(*) FROM security_scans WHERE scan_status='error'").fetchone()[0]}
    def _upload_reasons(self, path: Path, policy: UploadPolicy, declared_type: str | None) -> tuple[str, str]:
        reasons: list[str] = []; name = path.name
        extension = path.suffix.lower(); head = path.read_bytes()[:16]
        if len(name) > policy.max_filename_length or not re.fullmatch(r"[A-Za-z0-9._-]+", name): reasons.append("INVALID_FILENAME")
        if extension not in policy.allowed: reasons.append("DISALLOWED_TYPE")
        if path.stat().st_size > policy.max_bytes: reasons.append("SIZE_LIMIT_EXCEEDED")
        if head.startswith((b"MZ", b"\x7fELF", b"#!")): reasons.append("EXECUTABLE_OR_SCRIPT")
        expected = policy.allowed.get(extension)
        if expected and not head.startswith(expected): reasons.append("MAGIC_BYTE_MISMATCH")
        detected = "application/zip" if head.startswith(b"PK\x03\x04") else ("application/x-executable" if head.startswith((b"MZ", b"\x7fELF", b"#!")) else "application/octet-stream")
        if declared_type and expected and declared_type == "application/pdf" and not head.startswith(b"%PDF-"): reasons.append("DECLARED_TYPE_MISMATCH")
        if digest(path) in policy.malicious_hashes: reasons.append("MALICIOUS_HASH")
        if head.startswith(b"PK\x03\x04"): reasons.extend(self._inspect_zip_path(path, policy))
        return detected, ",".join(reasons)
    def _inspect_zip_path(self, path: Path, policy: UploadPolicy, depth: int = 1) -> list[str]:
        """Open a path for ZIP inspection; this wrapper owns and closes the handle."""
        with path.open("rb") as stream:
            return self._inspect_zip_stream(stream, policy, depth)
    def _stream_size(self, stream: BinarySeekableReader) -> int:
        position = stream.tell(); stream.seek(0, 2); size = stream.tell(); stream.seek(position); return size
    def _stream_bytes(self, stream: BinarySeekableReader) -> bytes:
        position = stream.tell(); stream.seek(0); data = stream.read(); stream.seek(position); return data
    def _inspect_zip_stream(self, stream: BinarySeekableReader, policy: UploadPolicy, depth: int = 1) -> list[str]:
        """Metadata-first ZIP preflight; never writes or executes archive entries."""
        reasons: list[str] = []; started = time.monotonic()
        if depth > policy.max_archive_depth: return ["ARCHIVE_NESTING_EXCEEDED"]
        if self._stream_size(stream) > policy.max_archive_upload_bytes: return ["ARCHIVE_UPLOAD_TOO_LARGE"]
        try:
            with zipfile.ZipFile(stream) as archive:
                entries = archive.infolist(); total = sum(item.file_size for item in entries); archive_bytes = max(1, self._stream_size(stream))
                reasons.extend(self._validate_zip_structure(stream, entries, policy))
                if len(entries) > policy.max_archive_files or total > policy.max_archive_bytes: reasons.append("ARCHIVE_LIMIT_EXCEEDED")
                if total / archive_bytes > policy.max_total_compression_ratio: reasons.append("ARCHIVE_TOTAL_RATIO_EXCEEDED")
                names: set[str] = set(); offsets: set[int] = set()
                for item in entries:
                    if time.monotonic() - started > policy.max_archive_parse_seconds: reasons.append("ARCHIVE_PARSE_TIMEOUT"); break
                    try: name = self.safe_archive_name(item.filename, policy)
                    except ValueError as exc: reasons.append(str(exc)); continue
                    if item.flag_bits & 1: reasons.append("ENCRYPTED_ARCHIVE")
                    if not policy.allow_zip64 and (item.file_size >= zipfile.ZIP64_LIMIT or item.compress_size >= zipfile.ZIP64_LIMIT or b"\x01\x00" in item.extra): reasons.append("ZIP64_NOT_ALLOWED")
                    if item.header_offset in offsets: reasons.append("ARCHIVE_DUPLICATE_HEADER_OFFSET")
                    offsets.add(item.header_offset)
                    if name.casefold() in names: reasons.append("ZIP_DUPLICATE_NORMALIZED_PATH")
                    names.add(name.casefold())
                    mode = (item.external_attr >> 16) & 0o170000
                    if mode not in (0, 0o100000, 0o040000): reasons.append("ARCHIVE_UNSAFE_ENTRY_TYPE")
                    if item.file_size > policy.max_archive_entry_bytes: reasons.append("ARCHIVE_ENTRY_LIMIT_EXCEEDED")
                    if item.compress_size and item.file_size / item.compress_size > policy.max_compression_ratio: reasons.append("ARCHIVE_COMPRESSION_RATIO_EXCEEDED")
                    if name.lower().endswith((".zip", ".jar", ".docx", ".xlsx")) and item.file_size <= policy.max_archive_entry_bytes:
                        try: reasons.extend(self._inspect_zip_stream(io.BytesIO(archive.read(item)), policy, depth + 1))
                        except (RuntimeError, zipfile.BadZipFile): reasons.append("ARCHIVE_NESTED_INSPECTION_ERROR")
        except (OSError, UnicodeDecodeError, zipfile.BadZipFile): reasons.append("ZIP_INVALID_NAME")
        return list(dict.fromkeys(reasons))
    def safe_archive_name(self, name: str, policy: UploadPolicy) -> str:
        """Strictly accept only unambiguous relative POSIX archive member names."""
        if not isinstance(name, str): raise ValueError("ZIP_INVALID_NAME")
        name = unicodedata.normalize("NFC", name)
        if not name or "\x00" in name or any(ord(char) < 32 for char in name): raise ValueError("ZIP_INVALID_NAME")
        if ":" in name: raise ValueError("ARCHIVE_NTFS_ADS_NAME")
        if "\\" in name: raise ValueError("ZIP_BACKSLASH_PATH")
        if any(char in '<>"|?*' for char in name): raise ValueError("ARCHIVE_WINDOWS_UNSAFE_NAME")
        if name.startswith("/") or name.startswith("//"): raise ValueError("ZIP_ABSOLUTE_PATH")
        if re.match(r"^[A-Za-z]:", name): raise ValueError("ZIP_WINDOWS_DRIVE_PATH")
        if "//" in name: raise ValueError("ZIP_REPEATED_SEPARATOR")
        clean = name.rstrip("/"); parts = PurePosixPath(clean).parts
        if not clean or any(part in ("", ".", "..") for part in parts): raise ValueError("ZIP_TRAVERSAL_PATH")
        if len(clean) > policy.max_archive_path_length or len(parts) > policy.max_archive_path_depth: raise ValueError("ZIP_PATH_LIMIT_EXCEEDED")
        if any(part.startswith(" ") or part.endswith((" ", ".")) for part in parts): raise ValueError("ARCHIVE_WINDOWS_TRAILING_DOT_OR_SPACE")
        reserved = {"CON", "PRN", "AUX", "NUL", *(f"COM{i}" for i in range(1, 10)), *(f"LPT{i}" for i in range(1, 10))}
        if any(part.split(".")[0].upper() in reserved for part in parts): raise ValueError("ARCHIVE_WINDOWS_RESERVED_NAME")
        return "/".join(parts)
    def _validate_zip_structure(self, stream: BinarySeekableReader, entries: list[zipfile.ZipInfo], policy: UploadPolicy) -> list[str]:
        """Validate local headers independently of zipfile's extraction behavior."""
        data = self._stream_bytes(stream)
        reasons: list[str] = []; offsets: dict[int, str] = {}; ranges: list[tuple[int, int]] = []; normalized: set[str] = set()
        for item in entries:
            offset = item.header_offset; name = item.filename.replace("\\", "/").rstrip("/")
            if name in normalized: reasons.append("ZIP_DUPLICATE_NORMALIZED_PATH")
            normalized.add(name)
            if offset < 0 or offset + 30 > len(data): reasons.append("ZIP_LOCAL_HEADER_OFFSET_OUT_OF_RANGE"); continue
            if offset in offsets: reasons.append("ZIP_DUPLICATE_LOCAL_HEADER_OFFSET"); continue
            offsets[offset] = name
            if data[offset:offset + 4] != b"PK\x03\x04": reasons.append("ZIP_INVALID_LOCAL_HEADER_SIGNATURE"); continue
            try: _, _, flags, method, _, _, crc, compressed, expanded, name_length, extra_length = struct.unpack_from("<IHHHHHIIIHH", data, offset)
            except struct.error: reasons.append("ZIP_INVALID_LOCAL_HEADER_SIGNATURE"); continue
            name_start, data_start = offset + 30, offset + 30 + name_length + extra_length
            if data_start > len(data): reasons.append("ZIP_ENTRY_DATA_RANGE_INVALID"); continue
            encoding = "utf-8" if flags & 0x800 else "cp437"
            try: local_name = data[name_start:name_start + name_length].decode(encoding).replace("\\", "/").rstrip("/")
            except UnicodeDecodeError: reasons.append("ZIP_INVALID_NAME"); continue
            if local_name != name or method != item.compress_type or flags != item.flag_bits: reasons.append("ZIP_CENTRAL_LOCAL_HEADER_MISMATCH")
            # Data-descriptor entries may have zero local CRC/sizes; otherwise require agreement.
            if not flags & 0x08 and (crc != item.CRC or compressed != item.compress_size or expanded != item.file_size): reasons.append("ZIP_CENTRAL_LOCAL_HEADER_MISMATCH")
            end = data_start + item.compress_size
            if end < data_start or end > len(data): reasons.append("ZIP_ENTRY_DATA_RANGE_INVALID"); continue
            if any(data_start < prior_end and prior_start < end for prior_start, prior_end in ranges): reasons.append("ZIP_OVERLAPPING_COMPRESSED_DATA")
            ranges.append((data_start, end))
        return list(dict.fromkeys(reasons))
    def extract_zip_safely(self, archive_path: Path, sandbox: Path, policy: UploadPolicy, scanner: Any | None = None, file_id: str | None = None) -> list[Path]:
        """Extract verified members to generated paths; fail closed and clean temp output."""
        reasons = self._inspect_zip_path(archive_path, policy)
        if reasons: raise ValueError("archive preflight failed: " + ",".join(reasons))
        sandbox.mkdir(parents=True, exist_ok=True); root = sandbox.resolve(); generated_id = key(file_id or str(uuid.uuid4())); output_root = (root / generated_id).resolve(); total = 0; output: list[Path] = []; started = time.monotonic(); scanner = scanner or FailClosedScanner()
        if root not in output_root.parents: raise ValueError("ZIP_PATH_ESCAPES_SANDBOX")
        try:
            with zipfile.ZipFile(archive_path) as archive:
                for index, info in enumerate(archive.infolist()):
                    if info.is_dir(): continue
                    if time.monotonic() - started > policy.max_archive_parse_seconds: raise TimeoutError("archive extraction timeout")
                    clean_name = self.safe_archive_name(info.filename, policy)
                    # Archive names are metadata only; writes use server-generated IDs.
                    destination = (output_root / f"{index:08d}{Path(clean_name).suffix.lower()}").resolve()
                    if output_root not in destination.parents or destination.suffix.lower() not in policy.allowed: raise ValueError("ZIP_PATH_ESCAPES_SANDBOX")
                    destination.parent.mkdir(parents=True, exist_ok=True); written = 0
                    with archive.open(info) as source, destination.open("xb") as target:
                        while chunk := source.read(64 * 1024):
                            written += len(chunk); total += len(chunk)
                            if written > policy.max_archive_entry_bytes or total > policy.max_archive_bytes: raise ValueError("actual archive expansion limit exceeded")
                            target.write(chunk)
                    expected = policy.allowed[destination.suffix.lower()]
                    if expected and not destination.read_bytes()[:len(expected)].startswith(expected): raise ValueError("ARCHIVE_MEMBER_MAGIC_BYTE_MISMATCH")
                    result = scanner.scan(destination)
                    if result.status != "clean": raise ValueError("ARCHIVE_MEMBER_SCAN_NOT_CLEAN")
                    output.append(destination)
            return output
        except Exception:
            if output_root.exists(): shutil.rmtree(output_root)
            raise
    def secure_upload(self, path: Path, source_id: str, uploader_id: str, source_ip: str | None = None, declared_type: str | None = None, policy: UploadPolicy = DEFAULT_UPLOAD_POLICY, scanner: Any | None = None, source_key: str | None = None) -> str:
        """Scan a private-inbox file. Nothing reaches normal processing until clean."""
        path = path.resolve()
        if path.parent != (self.root / "inbox").resolve(): raise ValueError("uploads must be in the private inbox")
        rule = self.matching_rule(path); source_key = source_key or path.name; record = self.register_file(path, source_id, source_key, rule); job = self.claim_job(record["id"], "security-scan")
        if not job["claimed"]: return record["id"]
        detected, reason_text = self._upload_reasons(path, policy, declared_type); reasons = tuple(x for x in reason_text.split(",") if x)
        result = scanner.scan(path) if scanner else FailClosedScanner().scan(path)
        status = "clean" if not reasons and result.status == "clean" else ("infected" if result.status == "infected" else "blocked")
        self.db.execute("INSERT OR REPLACE INTO security_scans VALUES (?,?,?,?,?,?,?,?,?,?,?,?)", (record["id"], uploader_id, source_ip, path.name, declared_type, detected, status, result.engine, result.version, json.dumps(reasons + result.reasons), now(), None)); self.db.commit()
        if status != "clean":
            severity = "critical" if any(x in reasons + result.reasons for x in ("MALICIOUS_HASH", "EXECUTABLE_OR_SCRIPT", "MALWARE")) or result.status == "infected" else "high"
            archive_security = any(code in reasons for code in ("ARCHIVE_NTFS_ADS_NAME", "ARCHIVE_WINDOWS_UNSAFE_NAME", "ARCHIVE_WINDOWS_RESERVED_NAME", "ARCHIVE_WINDOWS_TRAILING_DOT_OR_SPACE", "ZIP_TRAVERSAL_PATH", "ZIP_DUPLICATE_NORMALIZED_PATH", "ARCHIVE_UNSAFE_ENTRY_TYPE"))
            primary = "SECURITY_SCAN_NOT_CLEAN" if archive_security or result.status != "clean" else "FILE_UPLOAD_POLICY_FAILURE"
            self.quarantine_file(record, job, ValueError(",".join(reasons + result.reasons) or "SCAN_NOT_CLEAN"), primary, "security_scan", archive_security, reasons + result.reasons)
            self._begin(); event_key = key(record["id"], WORKFLOW_VERSION, "security.file_upload_quarantined"); payload = {"severity": severity, "file_id": record["id"], "source": source_id, "uploader_id": uploader_id, "sha256": record["checksum_sha256"], "reason_codes": reasons + result.reasons, "scan_status": status, "quarantine_reference": f"quarantine://security/{record['id']}"}; self.db.execute("INSERT OR IGNORE INTO outbox_events VALUES (?,?,?,?,?,?,?)", (str(uuid.uuid4()), event_key, "security.file_upload_quarantined", json.dumps(payload, sort_keys=True), "pending", now(), None)); self.db.execute("COMMIT"); return record["id"]
        self.db.execute("UPDATE security_scans SET released_at=? WHERE file_id=?", (now(), record["id"])); self.db.commit(); self.complete_job(job, {"status": "clean"}); return self.ingest(path, source_id, source_key)
    def security_release(self, file_id: str, approved: bool, scanner: Any) -> str:
        if not approved: raise PermissionError("explicit security approval is required")
        record = self.db.execute("SELECT * FROM file_records WHERE id=? AND state IN ('quarantine','security_quarantine')", (file_id,)).fetchone()
        if record is None: raise ValueError("security-quarantined file not found")
        evidence = Path(record["quarantine_path"]); candidate = self.root / "inbox" / self.db.execute("SELECT original_name FROM security_scans WHERE file_id=?", (file_id,)).fetchone()[0]; shutil.copy2(evidence, candidate)
        return self.secure_upload(candidate, record["source_id"], "security-review", scanner=scanner, source_key=f"{record['source_key']}:security-release:{record['checksum_sha256'][:12]}")
    def ingest_batch(self, paths: list[Path], source_id: str = "local") -> list[dict[str, str]]:
        """Per-file isolation with an explicit outcome for every attempted input."""
        results: list[dict[str, str]] = []
        for path in paths:
            try: results.append({"path": str(path), "file_id": self.ingest(path, source_id), "status": "accepted"})
            except Exception as exc: results.append({"path": str(path), "status": "rejected", "error_code": type(exc).__name__})
        return results
    def reprocess(self, quarantined_file_id: str, replacement: Path, approved: bool, actor: str = "operator") -> str:
        if not approved or actor not in ("operator", "security-review"): raise PermissionError("authorized explicit approval is required for reprocessing")
        old = self.db.execute("SELECT * FROM file_records WHERE id=? AND state='quarantine'", (quarantined_file_id,)).fetchone()
        if old is None or not replacement.is_file(): raise ValueError("quarantined record or replacement is invalid")
        self._begin(); self._audit(quarantined_file_id, "reprocess.requested", old["state"], old["state"], requested_by=actor); self._audit(quarantined_file_id, "reprocess.approved", old["state"], old["state"], approved_by=actor); self.db.execute("COMMIT")
        candidate = self.root / "inbox" / replacement.name; shutil.copy2(replacement, candidate)
        self._begin(); self._audit(quarantined_file_id, "reprocess.started", old["state"], old["state"], started_by=actor); self.db.execute("COMMIT")
        new_id = self.ingest(candidate, old["source_id"], f"{old['source_key']}:reprocess:{digest(candidate)[:12]}")
        self._begin(); self.db.execute("UPDATE file_records SET replaces_file_id=? WHERE id=?", (quarantined_file_id, new_id)); self._audit(quarantined_file_id, "reprocess.completed", old["state"], old["state"], replacement_file_id=new_id, completed_by=actor); self.db.execute("COMMIT"); return new_id
    def request_purge(self, file_id: str, actor: str, approved: bool = False) -> None:
        """Record a two-person purge workflow; this local slice never deletes evidence."""
        if actor not in ("retention-officer", "security-review"): raise PermissionError("purge authority required")
        self._begin()
        try:
            action_id = str(uuid.uuid4()); self.db.execute("INSERT INTO retention_actions VALUES (?,?,?,?,?,?,?,?,?)", (action_id, file_id, "purge", actor, actor if approved else None, None, now(), now() if approved else None, None)); self._audit(file_id, "purge.approved" if approved else "purge.requested", None, None, requested_by=actor); self.db.execute("COMMIT")
        except Exception: self.db.execute("ROLLBACK"); raise
    def set_legal_hold(self, file_id: str, enabled: bool, actor: str) -> None:
        if actor not in ("retention-officer", "security-review"): raise PermissionError("retention authority required")
        self._begin()
        try:
            self.db.execute("UPDATE evidence_artifacts SET legal_hold=? WHERE file_id=?", (int(enabled), file_id)); self._audit(file_id, "legal_hold.changed", None, None, changed_by=actor, enabled=enabled); self.db.execute("COMMIT")
        except Exception: self.db.execute("ROLLBACK"); raise
    def set_retention(self, file_id: str, retention_until: str | None, actor: str) -> None:
        if actor not in ("retention-officer", "security-review"): raise PermissionError("retention authority required")
        self._begin()
        try:
            self.db.execute("UPDATE evidence_artifacts SET retention_until=? WHERE file_id=?", (retention_until, file_id)); self._audit(file_id, "retention.changed", None, None, changed_by=actor, retention_until=retention_until); self.db.execute("COMMIT")
        except Exception: self.db.execute("ROLLBACK"); raise
    def execute_purge(self, file_id: str, actor: str) -> None:
        """Record approved purge execution; deletion is intentionally out of scope."""
        if actor != "retention-officer": raise PermissionError("purge execution authority required")
        self._begin()
        try:
            pending = self.db.execute("SELECT id FROM retention_actions WHERE file_id=? AND action='purge' AND approved_at IS NOT NULL AND executed_at IS NULL", (file_id,)).fetchone()
            held = self.db.execute("SELECT count(*) FROM evidence_artifacts WHERE file_id=? AND legal_hold=1", (file_id,)).fetchone()[0]
            if pending is None or held: raise PermissionError("approved purge without legal hold required")
            self.db.execute("UPDATE retention_actions SET executed_by=?,executed_at=? WHERE id=?", (actor, now(), pending["id"])); self._audit(file_id, "purge.executed", None, None, executed_by=actor); self.db.execute("COMMIT")
        except Exception: self.db.execute("ROLLBACK"); raise
    def schedule_retry(self, job: sqlite3.Row, error: Exception) -> int | None:
        """Persist the required 1/5/15-minute retry delay; never retry forever."""
        attempt = int(job["attempt_count"])
        if attempt > len(RETRY_DELAYS_MINUTES): self.require_recovery(job, error); return None
        delay = RETRY_DELAYS_MINUTES[attempt - 1]
        lease = (datetime.now(UTC) + timedelta(minutes=delay)).isoformat(timespec="seconds")
        self._begin()
        try:
            self.db.execute("UPDATE job_executions SET status='failed',failure_type='transient',error_code=?,error_message=?,locked_until=? WHERE id=? AND status='running'", (type(error).__name__, str(error), lease, job["id"])); self.db.execute("UPDATE file_records SET state='retry_wait',updated_at=? WHERE id=? AND state='processing'", (now(), job["file_id"])); self._audit(job["file_id"], "job.retry_scheduled", "processing", "retry_wait", job["operation_key"], delay_minutes=delay); self.db.execute("COMMIT"); return delay
        except Exception: self.db.execute("ROLLBACK"); raise
    def ingest(self, path: Path, source_id: str = "local", source_key: str | None = None) -> str:
        path = path.resolve(); source_key = source_key or path.name
        if not path.is_file() or path.parent not in ((self.root / "inbox").resolve(), (self.root / "staging").resolve()): raise ValueError("input must be in inbox or staging")
        if datetime.now(UTC).timestamp() - path.stat().st_mtime < self.stable_seconds: raise ValueError("upload is not yet stable")
        rule = self.matching_rule(path); record = self.register_file(path, source_id, source_key, rule); job = self.claim_job(record["id"], "process")
        if not job["claimed"]: return record["id"]
        try:
            if rule is None: raise ValueError("ambiguous or unknown filename")
            self.checkpoint(job, "source_verified")
            if self.transition(record["id"], "inbox", "staging", job["operation_key"]): path = self.move_with_intent(record["id"], path, self.root / "staging" / path.name)
            self.transition(record["id"], "staging", "validating", job["operation_key"]); self.validate(path, rule); self.checkpoint(job, "validated")
            if self.transition(record["id"], "validating", "processing", job["operation_key"]): path = self.move_with_intent(record["id"], path, self.root / "processing" / path.name)
            self.checkpoint(job, "output_write_started"); self.write_result(record["id"], "file-version", {"checksum": record["checksum_sha256"]}); self.checkpoint(job, "output_written")
            path = self.move_with_intent(record["id"], path, self.root / "archive" / rule.destination / path.name); self.checkpoint(job, "output_verified", digest(path)); self.transition(record["id"], "processing", "output_verified", job["operation_key"])
            self.commit_completion(job, {"status": "complete"}); return record["id"]
        except Exception as exc:
            current = self.db.execute("SELECT state,current_path FROM file_records WHERE id=?", (record["id"],)).fetchone()
            if isinstance(exc, ValueError):
                message = str(exc).lower()
                reason = "FILE_VALIDATION_SCHEMA_FAILURE" if "column" in message or "row count" in message else "FILE_FORMAT_MALFORMED"
                self.quarantine_file(record, job, exc, reason, "validation")
            elif isinstance(exc, OSError): self.schedule_retry(job, exc)
            else: self.require_recovery(job, exc)
            return record["id"]
    def relay_outbox(self, publisher) -> int:
        count = 0
        for event in self.db.execute("SELECT * FROM outbox_events WHERE status='pending' ORDER BY created_at").fetchall():
            publisher(dict(event)); self.db.execute("UPDATE outbox_events SET status='published',published_at=? WHERE id=?", (now(), event["id"])); count += 1
        return count
    def reconcile(self) -> list[str]:
        alerts = []
        for intent in self.db.execute("SELECT * FROM move_intents WHERE status='pending'").fetchall():
            source, target = Path(intent["source_path"]), Path(intent["target_path"]); temporary = Path(intent["temporary_path"]) if intent["temporary_path"] else None
            if target.exists() and digest(target) == intent["checksum_sha256"]: self.db.execute("UPDATE move_intents SET status='complete',completed_at=? WHERE id=?", (now(), intent["id"])); self.db.execute("UPDATE file_records SET current_path=? WHERE id=?", (str(target), intent["file_id"]))
            elif temporary and temporary.exists() and digest(temporary) == intent["checksum_sha256"] and not target.exists():
                target.parent.mkdir(parents=True, exist_ok=True); os.replace(temporary, target); self.db.execute("UPDATE move_intents SET status='complete',completed_at=? WHERE id=?", (now(), intent["id"])); self.db.execute("UPDATE file_records SET current_path=? WHERE id=?", (str(target), intent["file_id"]))
            elif source.exists(): alerts.append(f"incomplete move: {intent['file_id']}")
            else:
                self.db.execute("UPDATE file_records SET state='recovery_required' WHERE id=? AND state NOT IN ('complete','archived','quarantine','security_quarantine')", (intent["file_id"],)); alerts.append(f"unsafe missing or conflicting move: {intent['file_id']}")
        for job in self.db.execute("SELECT * FROM job_executions WHERE status='running' AND locked_until < ?", (now(),)).fetchall():
            self.db.execute("UPDATE job_executions SET status='recovery_required',failure_type='unknown',recovery_required=1 WHERE id=?", (job["id"],)); self.db.execute("UPDATE file_records SET state='recovery_required' WHERE id=? AND state='processing'", (job["file_id"],)); alerts.append(f"expired lease: {job['file_id']}")
        self.db.commit(); return alerts

def main() -> int:
    p = argparse.ArgumentParser(); p.add_argument("root", type=Path); p.add_argument("registry", type=Path); p.add_argument("--reconcile", action="store_true"); p.add_argument("--stable-seconds", type=int, default=30); a = p.parse_args()
    flow = Workflow(a.root, load_registry(a.registry), a.stable_seconds)
    try:
        print(json.dumps({"alerts": flow.reconcile()} if a.reconcile else {"file_ids": [flow.ingest(x) for s in ("inbox", "staging") for x in sorted((a.root/s).iterdir()) if x.is_file()]}))
    finally: flow.close()
    return 0
if __name__ == "__main__": raise SystemExit(main())
