# File pipeline specification

## Goal and nonfunctional requirements

Build a proactive, self-healing, security-first file pipeline that prevents,
detects, isolates, recovers from, and audits missing, misplaced, duplicate,
corrupt, unsafe, late, and invalid files. One failed file must never block
unrelated files. Database state is authoritative; all timestamps are UTC;
original uploads are never automatically overwritten or deleted; all production
actions are deterministic and idempotent.

## Status definitions

Proposed: candidate only. Planned: approved specification, no verified delivery.
In progress: implementation underway. Blocked: needs a decision/dependency.
Implemented: code exists but verification/documentation is incomplete. Complete:
all acceptance criteria and quality checks are recorded. Deferred: intentionally
postponed. Deprecated: not for new use.

## Feature registry

| ID | Name | Priority | Status | Dependencies | Code location | Test location | Last verified |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F-001 | File lifecycle state machine | P0 | Complete | database | `src/file_workflow.py` | `tests/test_file_workflow.py` | 2026-08-08 |
| F-002 | Idempotent jobs and duplicate events | P0 | Complete | F-001 | `src/file_workflow.py` | `tests/test_file_workflow.py` | 2026-08-08 |
| F-003 | Recovery, checkpoints, leases, reconciliation | P0 | Complete | F-001,F-002 | `src/file_workflow.py` | `tests/test_file_workflow.py` | 2026-08-08 |
| F-004 | Corrupt-file quarantine isolation | P0 | Complete | F-001,F-003 | `src/file_workflow.py` | `tests/test_file_workflow.py` | 2026-08-08 |
| F-005 | Suspicious-upload alerts | P0 | Planned | F-004 | TBD | TBD | — |
| F-006 | Encrypted archives and isolated extraction | P0 | Planned | F-005 | TBD | TBD | — |
| F-007 | Compression/decompression-bomb detection | P0 | Planned | F-006 | TBD | TBD | — |
| F-008 | ZIP offset/overlap detection | P0 | Planned | F-006 | TBD | TBD | — |
| F-009 | Zip Slip prevention | P0 | Planned | F-006 | TBD | TBD | — |
| F-010 | NTFS ADS and Windows-safe extraction | P0 | Complete | F-006,F-009 | `src/file_workflow.py` | `tests/test_file_workflow.py` | 2026-08-08 |
| F-011 | AI ambiguity classification and cache | P1 | Planned | F-002 | TBD | TBD | — |
| F-012 | Expected-file monitoring/anomalies | P1 | Planned | F-001,F-002 | TBD | TBD | — |

Conflict: the working tree contains uncommitted prototype pipeline code, while
this registry remains Planned until its implementation is intentionally scoped,
tested, and verified against this specification.

## State model

Normal path: `inbox -> staging -> validating -> processing -> output_verified
-> complete -> archive`. Exception states: `retry_wait`,
`recovery_required`, `quarantine`, and `security_quarantine`. Every transition
has an explicit allowed prior state. Unknown state is never success.

## Idempotency

`file_id` is server-generated. Persist immutable `tenant_id`, `source_id`,
`source_event_id`, `source_object_key`, `source_object_version`,
`source_delivery_id`, byte size, and content SHA-256 separately. Identity rules
are versioned (`v1`): the same source event is a replay; otherwise the same
source object version plus SHA-256 is a replay. Reusing a source key with a new
object version creates a new file version; reusing an object version with
different content is a conflict. Equal contents under distinct legitimate
events/deliveries are separate records, not global duplicates.

An operation key is SHA-256 of file ID, workflow version, and operation name.
Unique constraints protect delivery identities, executions, outbox events, and
business outputs. Active jobs use leases; expired leases are reconciled.
Completed operations store their result. Guarded transitions and upserts occur
transactionally with an outbox; consumers must also deduplicate.

## Recovery and reconciliation

Checkpoints are `claimed`, `source_verified`, `validated`,
`output_write_started`, `output_written`, `output_verified`,
`state_committed`, and `event_queued`. Failures are transient, permanent,
conflict, or unknown. Transient retries wait 1, 5, then 15 minutes. Permanent
validation/security failures quarantine. Unknown, crash, or incomplete-write
failures require recovery. Reconciliation runs every 30 minutes and after an
outage/deployment, comparing database state, source/temp/final outputs,
checksums, leases, and outbox delivery. It never blindly deletes data.

## Quarantine

Quarantine is per-file; security quarantine is separate and restricted. Retain
original evidence, SHA-256, source, original path/name, reason, UTC time,
stage, workflow version, attempt count, manifest, and validation report.
Reprocessing requires explicit approval, a new version/identity, full normal
validation, and lineage. No automatic blind redrive is allowed.

## F-001–F-004 implementation record

**State and ownership.** `archived`, `quarantine`, and
`security_quarantine` are terminal. `recovery_required` is non-terminal and
may resume only from a durable checkpoint into staging, validation, processing,
or output verification, or enter quarantine. Intake owns inbox/staging,
validation owns validating, a leased job owns processing/retry, completion owns
output verification/complete, and reconciliation owns recovery. Job-attempt
states (`running`, `failed`, `retry_wait`, `recovery_required`, `succeeded`)
are distinct from the file lifecycle.

**Failure mapping.** Transient errors retry after 1, 5, and 15 minutes, then
require recovery. Permanent validation errors normally quarantine; security
errors security-quarantine; conflicts and unknown errors require recovery and
escalation. SQLite runs locally in WAL mode with a 2-second busy timeout and
bounded lock retries; transactions do not include hashing, validation, moves,
or writes.

**Audit/evidence.** Audit is append-only for evidence capture, quarantine,
reprocess request/approval/start/completion, retention/legal-hold changes, and
purge request/approval/execution. Reconciliation never changes evidence bytes,
classification, storage ID, hold, or retention.

**Required verification.** Test exact source-event replay, changed-content
versions, terminal transition rejection, concurrent claims and lock contention,
move and outbox crash recovery, fail-closed unknown validation/scanning,
evidence hashes, unauthorized reprocess/purge, retries, reconciliation, and
per-file isolation.

**Legacy migration:** the local SQLite migration rebuilds only the obsolete
delivery uniqueness constraint inside an exclusive transaction, preserves
existing record IDs and foreign-key lineage, and verifies foreign keys before
commit.

## Archive security and observability

Archives are signature-detected and preflighted. Limits apply to compressed and
expanded size, entry count, ratio, nesting, parser/extraction time, CPU, memory,
disk, and processes. Metadata is only an early gate; sandbox extraction applies
actual limits, true-type validation, and malware scanning before release to
staging. Alerts and metrics cover received, processed, duplicate, retried,
quarantined, security-quarantined, missing, late, stuck, scan latency/failure,
alert failure, and reconciliation repairs.

## Feature acceptance and verification records

Every feature requires deterministic acceptance criteria, unit/integration
tests, recovery/concurrency/security tests where applicable, documentation/ADR
updates, and a recorded verification command/result.

| Feature | Purpose and security impact | Acceptance and required tests | ADR/docs | Implementation / verification |
| --- | --- | --- | --- | --- |
| F-001 | Constrain lifecycle and prevent invalid routing. | Guard each transition; test allowed/denied transitions and concurrent advances. | ADR-001; runbook | `src/file_workflow.py` / `make verify` passed 2026-08-08 |
| F-002 | Stop duplicate effects. | Versioned delivery identity, unique jobs/outbox/outputs; test replay, changed content, and concurrent claims. | ADR-001 | `src/file_workflow.py` / `make verify` passed 2026-08-08 |
| F-003 | Resume safely after faults. | Checkpoints, leases, 1/5/15 retries, contention, move/outbox reconciliation. | ADR-001; runbook | `src/file_workflow.py` / `make verify` passed 2026-08-08 |
| F-004 | Isolate corrupt data. | Immutable evidence hashes, reason codes, authorization, batch isolation, and reprocess lineage. | Security; runbook | `src/file_workflow.py` / `make verify` passed 2026-08-08 |
| F-005 | Block unsafe uploads. | Private intake, signature/scan checks and deduplicated alerts; spoof/scan-error tests. | Security; runbook | Pending / Pending |
| F-006 | Contain archive risk. | Default-deny encrypted archives and sandbox extraction; encrypted/clean tests. | ADR-001; Security | Pending / Pending |
| F-007 | Stop expansion attacks. | Preflight and actual-byte limits; ratio/count/nesting/bomb tests. | Security | Pending / Pending |
| F-008 | Stop parser confusion. | Validate offsets, headers, ranges; duplicate/overlap/malformed tests. | Security | Pending / Pending |
| F-009 | Stop path escape. | Strict member validation and containment; traversal/path/link tests. | Security | Pending / Pending |
| F-010 | Stop ADS/Windows filename bypasses. | See F-010 record below. | ADR-001; Security | `src/file_workflow.py` / `make verify` passed 2026-08-08 |
| F-011 | Bound AI ambiguity handling. | Structured JSON only, cache by rule/version/permissions/data; no-action tests. | ADR-001 | Pending / Pending |
| F-012 | Detect missing/late anomalies. | Registry/SLA monitoring and alert tests. | Runbook | Pending / Pending |
| AUD-001–AUD-004 | CARINA durable receipts, bound approvals, trust state, and failure verification. | Hash-chain integrity, denial, expiry, target mutation, and exact-once tests. | ADR-002; Security; Runbook | `CARINAApprovalBoundary` / `swift test` passed 2026-08-08 |
| AUD-005, AUD-006, AUD-008 | Versioned capability allowlist, locked ActionPlan, and isolated batch compilation. | Version-key miss before validation, locked-plan mutation rejection, and valid/failed batch isolation. | ADR-002; Security; Runbook | `CARINAApprovalBoundary` / `swift test` passed 2026-08-08 |
| AUD-007 | Durable local ledger and transactional outbox recovery. | Atomic reserve/outbox insertion, restart recovery, duplicate reservation, completion suppression, and persisted-plan tamper checks. | ADR-002; Security; Runbook | `CARINAApprovalBoundary` / `swift test` passed 2026-08-08 |
| AUD-009 | Registry-integrated persistent approval runtime. | Registry-derived permission before replay reservation; SQLite restart persistence; cross-connection one-time token consumption; durable executor idempotency. | ADR-002; Security; Runbook | Implemented; 43 Swift tests passed 2026-08-12 |

## F-010 — NTFS ADS and Windows-safe archive extraction

**Purpose:** prevent archive member names from bypassing validation or writing
unsafe files on NTFS, Windows-compatible filesystems, or sandbox storage.

**Dependencies:** archive preflight, security quarantine, sandbox extraction.
**Security/data-integrity impact:** P0; one unsafe member quarantines the whole
archive and no archive-controlled name becomes an output path.

**Acceptance criteria:** NFC-normalize and strictly decode names; reject colon
ADS forms (`file.txt:evil`, `file.asax:.jpg`, `:stream`), Windows-forbidden
characters, null/control data, absolute/drive/UNC/backslash/traversal/repeated
separator paths, length/depth excess, trailing dots/spaces, reserved devices,
and normalized/case-folded collisions. Reject all links/special entries.
Quarantine rather than sanitize. Preflight before extraction; canonical
containment and exclusive creation immediately before writes. Generate physical
targets from file ID and entry index; retain member names as metadata only.
Scan and true-type validate every member before staging release.

**Reason codes:** `ARCHIVE_NTFS_ADS_NAME`, `ARCHIVE_WINDOWS_UNSAFE_NAME`,
`ARCHIVE_WINDOWS_RESERVED_NAME`, `ARCHIVE_WINDOWS_TRAILING_DOT_OR_SPACE`,
`ARCHIVE_PATH_ESCAPES_SANDBOX`, `ZIP_TRAVERSAL_PATH`,
`ZIP_DUPLICATE_LOCAL_HEADER_OFFSET`, `ZIP_OVERLAPPING_COMPRESSED_DATA`.

**Required tests:** ADS examples; drive/UNC/POSIX/traversal/backslash names;
reserved/trailing/null/control/invalid encoding/forbidden characters;
Unicode/case collisions; links/special entries; prefix containment; valid
nested generated-path extraction; quarantine evidence/audit/duplicate events.

**Documentation/ADR:** this document, Security Requirements, Operations
Runbook, and ADR-001. **Implementation:** `src/file_workflow.py` performs
strict NFC name validation, ADS/Windows rejection, generated hashed sandbox
paths, exclusive writes, member signature/scanner gates, and restricted
`security_quarantine` evidence/audit/outbox handling.

**Verification:** 2026-08-08 — `make verify` passed: Markdown lint, Python
compile checks, 60 unit/integration tests, dashboard build, token check, and
`git diff --check`. F-010 tests cover ADS inputs, Windows name variants,
Unicode collision, special entry, invalid member input, generated-path
containment, scan failure cleanup, and idempotent quarantine evidence/events.

## CARINA approval audit (AUD-001–AUD-004)

CARINA approval receipts contain only originating correlation ID, approval
fingerprint, displayed target, lifecycle status, UTC timestamp, and a hash
link to the prior receipt. They never retain raw command payloads, voice
recordings, credentials, or model output. A fingerprint binds the canonical
payload and exact displayed target. Tokens are short-lived, consumed once
before adapter execution, and invalid after replay or mutation. Terminal
statuses are `denied`, `expired`, `cancelled`, `failed-before-execution`,
`executed`, and `executed-with-warning`. The Trust Dashboard model exposes
Private Mode, bridge state, permission issues, and recent receipts.

## CARINA capability allowlist and locked plans (AUD-005, AUD-006, AUD-008)

The executable capability registry is an immutable deployment snapshot. The
allowlist key is exactly `(capability_id, version_major)`; a missing or
mismatched key fails before payload validation and never creates a runtime
schema. `ActionPlan` is compiled only from a matching reviewed capability and
contains the snapshot ID, capability ID/version, normalized parameters, target,
permissions, preflight results, expiry, nonce, and idempotency key. It does not
retain raw model text. Its deterministic locked-artifact hash covers each
execution-relevant field and is rechecked by the ledger before reserve,
dispatch, and finish.

Batch compilation is per action. Every proposal becomes either an executable
`ActionPlan` or a metadata-only `FailedCapabilityProposal` suitable for an
isolated DLQ writer; a failed proposal never blocks valid plans and cannot
reach an execution API. The current package provides in-process storage only;
production must replace the ledger and DLQ handoff with protected transactional
storage, outbox delivery, and least-privilege roles before multi-process use.
DLQ stubs retain correlation/tenant metadata, requested capability/version,
reason, and one-way hashes of the raw intent and suggested schema only. They
never retain raw intent, payload, or schema content. Batch and payload-size
limits turn only the offending item into a policy-rejected stub.

## CARINA durable ledger and outbox (AUD-007)

`DurableActionLedger` persists guarded ledger records, idempotency mappings,
and outbox entries in one locked, atomically replaced local store. Reservation
and pending-outbox insertion are one transaction. The stable outbox ID is the
executor idempotency key; incomplete entries are returned after restart for
at-least-once delivery, while completion atomically marks both the action state
and outbox entry terminal. Each persisted plan must pass locked-artifact
integrity verification before delivery.

This is a local-filesystem reference implementation with advisory locking,
suited to one host. It is not a distributed database, a cryptographic
provenance system, or an external execution guarantee.

## CARINA persistent approval runtime (AUD-009)

**Scope:** connect the command dispatcher to the immutable capability registry
and replace process-local replay, challenge, token, and idempotency state with
one SQLite-backed authority. The runtime composition root accepts only a
reviewed `AppIntentAdapter`; the current macOS app intentionally supplies none
and therefore gains no new execution permission.

**Acceptance criteria:** permission is registry-derived before replay
reservation; unknown inputs fail closed; replay and idempotency reservations
survive restart; issued tokens survive restart but can be consumed exactly
once; two independent database connections have one token-consumption winner;
database failures prevent execution.

**Implementation:** `PersistentApprovalBoundary`,
`ProductionCommandRouter`, and `SQLiteApprovalStateStore` under
`CARINAApprovalBoundary/Sources/Carina`.

**Verification:** 2026-08-12 — macOS `swift test --parallel` passed all\n43 tests. Repository Python 3.9 gates remain blocked by the pre-existing use\nof `datetime.UTC`, which requires Python 3.11 or later.
