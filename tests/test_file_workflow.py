import json
import io
import sqlite3
import tempfile
import threading
import unittest
import zipfile
from pathlib import Path

from src.file_workflow import ConflictError, ScanResult, UploadPolicy, Workflow, load_registry

RULE = {"name":"orders","source":"erp","schedule":"daily","filename_pattern":r"orders-\d{8}\.csv","extensions":[".csv"],"owner":"ops","sla_minutes":60,"destination":"orders","required_columns":["id","amount"],"column_types":{"id":"int","amount":"float"}}

class IdempotentWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.root=Path(self.temp.name)/"flow"; registry=Path(self.temp.name)/"rules.json"; registry.write_text(json.dumps({"expected_files":[RULE]})); self.rules=load_registry(registry)
    def tearDown(self): self.temp.cleanup()
    def flow(self): return Workflow(self.root, self.rules, stable_seconds=0)
    def put(self, name="orders-20260808.csv", content="id,amount\n1,2\n"):
        f=self.root/"inbox"/name; f.parent.mkdir(parents=True,exist_ok=True); f.write_text(content); return f
    def test_duplicate_delivery_has_one_file_result_and_one_complete_event(self):
        f=self.put(); w=self.flow(); first=w.ingest(f,"erp","orders-20260808.csv"); w.close()
        # Re-delivery is represented by another object copy with the same source key/version.
        f=self.put(); w=self.flow(); second=w.ingest(f,"erp","orders-20260808.csv")
        self.assertEqual(first,second); self.assertEqual(w.db.execute("SELECT count(*) FROM result_writes").fetchone()[0],1); self.assertEqual(w.db.execute("SELECT count(*) FROM file_records WHERE state='complete'").fetchone()[0],1); w.close()
    def test_concurrent_claim_has_one_owner(self):
        f=self.put(); w=self.flow(); record=w.register_file(f,"erp","key",w.rules[0]); w.close(); results=[]
        def claim():
            worker=self.flow(); results.append(worker.claim_job(record["id"],"import")); worker.close()
        a,b=threading.Thread(target=claim),threading.Thread(target=claim); a.start(); b.start(); a.join(); b.join()
        self.assertEqual(sum(x["claimed"] for x in results),1)
        verify=self.flow(); self.assertEqual(verify.db.execute("SELECT count(*) FROM job_executions").fetchone()[0],1); verify.close()
    def test_state_machine_rejects_invalid_or_terminal_transitions(self):
        w=self.flow(); record=w.register_file(self.put(),"erp","key",w.rules[0])
        with self.assertRaisesRegex(ValueError,"inbox -> complete"): w.transition(record["id"],"inbox","complete")
        self.assertTrue(w.transition(record["id"],"inbox","staging")); self.assertTrue(w.transition(record["id"],"staging","validating")); self.assertTrue(w.transition(record["id"],"validating","quarantine"))
        with self.assertRaisesRegex(ValueError,"quarantine -> staging"): w.transition(record["id"],"quarantine","staging")
        for terminal in ("archived","quarantine","security_quarantine"):
            w.db.execute("UPDATE file_records SET state=? WHERE id=?",(terminal,record["id"])); w.db.commit()
            with self.assertRaises(ValueError): w.transition(record["id"],terminal,"staging")
        w.close()
    def test_same_name_changed_content_is_new_version(self):
        w=self.flow(); one=w.ingest(self.put(content="id,amount\n1,2\n"),"erp","orders-20260808.csv"); self.put(content="id,amount\n1,3\n"); two=w.ingest(self.root/"inbox/orders-20260808.csv","erp","orders-20260808.csv")
        self.assertNotEqual(one,two); self.assertEqual(w.db.execute("SELECT count(*) FROM file_records").fetchone()[0],2); w.close()
    def test_source_event_replay_and_same_version_changed_content(self):
        w=self.flow(); path=self.put(); first=w.register_file(path,"erp","orders",w.rules[0],source_event_id="event-1",source_object_version="etag-1")
        self.assertEqual(first["id"],w.register_file(path,"erp","orders",w.rules[0],source_event_id="event-1",source_object_version="etag-1")["id"])
        path.write_text("id,amount\n1,3\n")
        with self.assertRaisesRegex(ConflictError,"FILE_SOURCE_VERSION_CONTENT_CONFLICT"): w.register_file(path,"erp","orders",w.rules[0],source_event_id="event-2",source_object_version="etag-1")
        self.assertNotEqual(first["id"],w.register_file(path,"erp","orders",w.rules[0],source_event_id="event-2",source_object_version="etag-2")["id"]); w.close()
    def test_legacy_identity_constraint_migrates_without_losing_lineage(self):
        self.root.mkdir(parents=True); database=sqlite3.connect(self.root/"workflow.sqlite3")
        database.executescript("CREATE TABLE file_records (id TEXT PRIMARY KEY, source_id TEXT NOT NULL, source_key TEXT NOT NULL, checksum_sha256 TEXT NOT NULL, byte_size INTEGER NOT NULL, workflow_version TEXT NOT NULL, rule_name TEXT, state TEXT NOT NULL, current_path TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, quarantine_path TEXT, quarantine_reason TEXT, replaces_file_id TEXT, UNIQUE(source_id,source_key,checksum_sha256)); CREATE TABLE job_executions (id TEXT PRIMARY KEY, file_id TEXT NOT NULL REFERENCES file_records(id));")
        source=self.root/"legacy.csv"; source.write_text("id,amount\n1,2\n"); checksum=__import__("hashlib").sha256(source.read_bytes()).hexdigest()
        database.execute("INSERT INTO file_records VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",("legacy","erp","orders",checksum,source.stat().st_size,"2","orders","complete",str(source),"2026-01-01","2026-01-01",None,None,None)); database.execute("INSERT INTO job_executions VALUES (?,?)",("legacy-job","legacy")); database.commit(); database.close()
        w=self.flow(); self.assertEqual(w.db.execute("SELECT count(*) FROM file_records WHERE id='legacy'").fetchone()[0],1); self.assertEqual(w.db.execute("PRAGMA foreign_key_check").fetchall(),[])
        replacement=w.register_file(source,"erp","orders",w.rules[0],source_event_id="new-event"); self.assertNotEqual(replacement["id"],"legacy"); w.close()
    def test_invalid_file_quarantines_and_creates_outbox_event(self):
        w=self.flow(); f=w.ingest(self.put(content="id\n1\n")); record=w.db.execute("SELECT * FROM file_records WHERE id=?",(f,)).fetchone(); self.assertEqual(record["state"],"quarantine"); self.assertTrue(Path(record["quarantine_path"]).exists()); self.assertTrue(Path(record["quarantine_path"]).with_name("manifest.json").exists()); self.assertEqual(w.db.execute("SELECT count(*) FROM outbox_events WHERE event_type='file.quarantined'").fetchone()[0],1); w.close()
    def test_evidence_hashes_are_recorded(self):
        w=self.flow(); file_id=w.ingest(self.put(content="id\n1\n")); artifacts=w.db.execute("SELECT * FROM evidence_artifacts WHERE file_id=?",(file_id,)).fetchall(); self.assertEqual({a["artifact_type"] for a in artifacts},{"original","manifest","validation-report"})
        for artifact in artifacts: self.assertEqual(__import__("hashlib").sha256(Path(artifact["path"]).read_bytes()).hexdigest(),artifact["checksum_sha256"])
        w.close()
    def test_outbox_retry_does_not_mark_failed_publish_as_done(self):
        w=self.flow(); w.ingest(self.put()); calls=[]
        with self.assertRaises(RuntimeError): w.relay_outbox(lambda event: (_ for _ in ()).throw(RuntimeError("down")))
        self.assertGreater(w.db.execute("SELECT count(*) FROM outbox_events WHERE status='pending'").fetchone()[0],0)
        w.relay_outbox(lambda event: calls.append(event["event_key"])); self.assertGreater(len(calls),0); w.close()
    def test_outbox_survives_completion_commit_before_publication(self):
        w=self.flow(); file_id=w.ingest(self.put()); w.close()  # Simulate a process loss before relay.
        w=self.flow(); sent=[]; w.relay_outbox(lambda event: sent.append(event["event_key"])); self.assertIn(file_id,[json.loads(row["payload"])["file_id"] for row in w.db.execute("SELECT payload FROM outbox_events WHERE status='published'")]); self.assertEqual(len(sent),1); w.close()
    def test_reconcile_repairs_verified_move_intent(self):
        w=self.flow(); f=self.put(); r=w.register_file(f,"erp","key",w.rules[0]); target=self.root/"staging"/f.name; target.parent.mkdir(exist_ok=True); target.write_bytes(f.read_bytes())
        w.db.execute("INSERT INTO move_intents VALUES (?,?,?,?,?,?,?,?,?)",("intent",r["id"],str(f),str(target),r["checksum_sha256"],"pending","2000-01-01",None,None)); w.db.commit(); self.assertEqual(w.reconcile(),[]); self.assertEqual(w.db.execute("SELECT status FROM move_intents WHERE id='intent'").fetchone()[0],"complete"); w.close()
    def test_busy_claim_retries_after_short_sqlite_contention(self):
        w=self.flow(); record=w.register_file(self.put(),"erp","busy",w.rules[0]); lock=sqlite3.connect(self.root/"workflow.sqlite3",timeout=0,isolation_level=None); lock.execute("BEGIN IMMEDIATE"); result=[]
        def claim():
            worker=self.flow(); result.append(worker.claim_job(record["id"],"import")["claimed"]); worker.close()
        thread=threading.Thread(target=claim); thread.start(); lock.execute("COMMIT"); thread.join(); lock.close(); self.assertEqual(result,[1]); w.close()
    def test_transient_retries_use_required_backoff(self):
        w=self.flow(); r=w.register_file(self.put(),"erp","key",w.rules[0]); job=w.claim_job(r["id"],"import")
        self.assertEqual(w.schedule_retry(job, OSError("temporary")),1)
        job=w.claim_job(r["id"],"import")
        self.assertFalse(job["claimed"]); w.close()
    def test_retry_exhaustion_requires_recovery_after_one_five_fifteen_minutes(self):
        w=self.flow(); record=w.register_file(self.put(),"erp","retry",w.rules[0]); w.transition(record["id"],"inbox","staging"); w.transition(record["id"],"staging","validating"); w.transition(record["id"],"validating","processing")
        job=w.claim_job(record["id"],"import")
        for delay in (1,5,15):
            self.assertEqual(w.schedule_retry(job,OSError("temporary")),delay)
            w.db.execute("UPDATE job_executions SET locked_until='2000-01-01' WHERE id=?",(job["id"],)); w.db.commit(); job=w.claim_job(record["id"],"import")
        self.assertIsNone(w.schedule_retry(job,OSError("temporary")))
        self.assertEqual(w.db.execute("SELECT state FROM file_records WHERE id=?",(record["id"],)).fetchone()[0],"recovery_required"); w.close()
    def test_batch_isolates_failed_input_and_reports_it(self):
        w=self.flow(); valid=self.put(); outside=Path(self.temp.name)/"not-in-inbox.csv"; outside.write_text("id,amount\n2,3\n")
        outcomes=w.ingest_batch([outside,valid],"erp")
        self.assertEqual([outcome["status"] for outcome in outcomes],["rejected","accepted"]); self.assertIn("error_code",outcomes[0]); w.close()
    def test_expired_lease_becomes_recovery_required_not_complete(self):
        w=self.flow(); r=w.register_file(self.put(),"erp","key",w.rules[0]); job=w.claim_job(r["id"],"import")
        w.transition(r["id"],"inbox","staging"); w.transition(r["id"],"staging","validating"); w.transition(r["id"],"validating","processing")
        w.db.execute("UPDATE job_executions SET locked_until='2000-01-01' WHERE id=?",(job["id"],)); w.db.commit(); w.reconcile()
        self.assertEqual(w.db.execute("SELECT state FROM file_records WHERE id=?",(r["id"],)).fetchone()[0],"recovery_required"); self.assertEqual(w.db.execute("SELECT status FROM job_executions WHERE id=?",(job["id"],)).fetchone()[0],"recovery_required"); w.close()
    def test_reprocessing_requires_approval_and_preserves_lineage(self):
        w=self.flow(); old=w.ingest(self.put(content="id\n1\n")); replacement=Path(self.temp.name)/"fixed.csv"; replacement.write_text("id,amount\n1,2\n")
        with self.assertRaises(PermissionError): w.reprocess(old,replacement,False)
        new=w.reprocess(old,replacement,True); self.assertEqual(w.db.execute("SELECT replaces_file_id FROM file_records WHERE id=?",(new,)).fetchone()[0],old); self.assertEqual(w.db.execute("SELECT state FROM file_records WHERE id=?",(old,)).fetchone()[0],"quarantine"); w.close()
    def test_unauthorized_reprocess_and_purge_are_rejected(self):
        w=self.flow(); old=w.ingest(self.put(content="id\n1\n")); fixed=Path(self.temp.name)/"fixed.csv"; fixed.write_text("id,amount\n1,2\n")
        with self.assertRaises(PermissionError): w.reprocess(old,fixed,True,actor="untrusted")
        with self.assertRaises(PermissionError): w.request_purge(old,"untrusted")
        w.set_legal_hold(old,True,"retention-officer"); w.request_purge(old,"retention-officer",approved=True)
        with self.assertRaises(PermissionError): w.execute_purge(old,"retention-officer")
        self.assertEqual(w.db.execute("SELECT count(*) FROM audit_events WHERE file_id=? AND event_type='legal_hold.changed'",(old,)).fetchone()[0],1)
        w.close()
    def test_spoofed_extension_and_scan_error_are_fail_closed(self):
        w=self.flow(); file=self.put(name="orders-20260808.csv",content="MZ malware")
        blocked=w.secure_upload(file,"vendor","user",declared_type="text/csv",scanner=type("Scanner",(),{"scan":lambda _,__: ScanResult("clean","test","1")})())
        self.assertEqual(w.db.execute("SELECT state FROM file_records WHERE id=?",(blocked,)).fetchone()[0],"quarantine"); self.assertEqual(w.db.execute("SELECT count(*) FROM outbox_events WHERE event_type='security.file_upload_quarantined'").fetchone()[0],1); w.close()
    def test_unknown_validation_and_scanner_results_fail_closed(self):
        w=self.flow(); w.validate=lambda path, rule: (_ for _ in ()).throw(RuntimeError("validator unavailable")); file_id=w.ingest(self.put())
        self.assertEqual(w.db.execute("SELECT state FROM file_records WHERE id=?",(file_id,)).fetchone()[0],"recovery_required")
        w.close(); w=self.flow(); blocked=w.secure_upload(self.put(name="orders-20260809.csv"),"vendor","user",scanner=type("Scanner",(),{"scan":lambda _,__: ScanResult("error","test","1")})())
        self.assertEqual(w.db.execute("SELECT state FROM file_records WHERE id=?",(blocked,)).fetchone()[0],"quarantine"); w.close()
    def test_malware_positive_and_oversized_upload_are_blocked(self):
        w=self.flow(); file=self.put(content="id,amount\n1,2\n")
        infected=w.secure_upload(file,"vendor","user",scanner=type("Scanner",(),{"scan":lambda _,__: ScanResult("infected","test","1",("MALWARE",))})()); self.assertEqual(w.db.execute("SELECT state FROM file_records WHERE id=?",(infected,)).fetchone()[0],"quarantine")
        big=self.put(name="orders-20260809.csv",content="id,amount\n1,2\n"); result=w.secure_upload(big,"vendor","user",policy=UploadPolicy({".csv":b""},max_bytes=2),scanner=type("Scanner",(),{"scan":lambda _,__: ScanResult("clean","test","1")})()); self.assertEqual(w.db.execute("SELECT state FROM file_records WHERE id=?",(result,)).fetchone()[0],"quarantine"); w.close()
    def test_security_release_requires_approval_and_rescans(self):
        w=self.flow(); blocked=w.secure_upload(self.put(),"vendor","user",scanner=type("Scanner",(),{"scan":lambda _,__: ScanResult("infected","test","1",("MALWARE",))})())
        with self.assertRaises(PermissionError): w.security_release(blocked,False,type("Scanner",(),{"scan":lambda _,__: ScanResult("clean","test","1")})())
        released=w.security_release(blocked,True,type("Scanner",(),{"scan":lambda _,__: ScanResult("clean","test","1")})()); self.assertNotEqual(released,blocked); self.assertEqual(w.db.execute("SELECT state FROM file_records WHERE id=?",(released,)).fetchone()[0],"complete"); w.close()
    def test_archive_preflight_blocks_bombs_and_traversal_without_extracting(self):
        w=self.flow(); archive=self.root/"inbox"/"orders-20260808.csv"; archive.parent.mkdir(parents=True,exist_ok=True)
        with zipfile.ZipFile(archive,"w",zipfile.ZIP_DEFLATED) as z: z.writestr("../../escape",b"x"); z.writestr("dense.txt",b"0"*10_000)
        policy=UploadPolicy({".csv":b"PK\x03\x04"},max_compression_ratio=2)
        reasons=w._inspect_zip_path(archive,policy); self.assertIn("ZIP_TRAVERSAL_PATH",reasons); self.assertIn("ARCHIVE_COMPRESSION_RATIO_EXCEEDED",reasons); self.assertFalse((self.root/"escape").exists()); w.close()
    def test_clean_archive_preflight_and_bounded_sandbox_extraction(self):
        w=self.flow(); archive=self.root/"inbox"/"clean.zip"; archive.parent.mkdir(parents=True,exist_ok=True)
        with zipfile.ZipFile(archive,"w",zipfile.ZIP_STORED) as z: z.writestr("report.csv",b"id,amount\n1,2\n")
        policy=UploadPolicy({".csv":b""},max_total_compression_ratio=10)
        clean=type("Scanner",(),{"scan":lambda _,__: ScanResult("clean","test","1")})(); self.assertEqual(w._inspect_zip_path(archive,policy),[]); files=w.extract_zip_safely(archive,self.root/"sandbox",policy,clean,"file-version"); self.assertEqual(files[0].read_text(),"id,amount\n1,2\n"); self.assertRegex(files[0].parent.name,r"^[0-9a-f]{64}$"); w.close()
    def test_zip_inspection_path_and_caller_stream_boundaries(self):
        w=self.flow(); archive=self.root/"inbox"/"boundary.zip"; archive.parent.mkdir(parents=True,exist_ok=True)
        with zipfile.ZipFile(archive,"w",zipfile.ZIP_STORED) as z: z.writestr("report.csv",b"id,amount\n1,2\n")
        policy=UploadPolicy({".csv":b""})
        self.assertEqual(w._inspect_zip_path(archive,policy),[])
        stream=io.BytesIO(archive.read_bytes()); self.assertEqual(w._inspect_zip_stream(stream,policy),[]); self.assertFalse(stream.closed); self.assertEqual(stream.read(1),b"P")
        w.close()
    def test_duplicate_local_header_offset_is_structurally_rejected(self):
        w=self.flow(); archive=self.root/"inbox"/"offset.zip"; archive.parent.mkdir(parents=True,exist_ok=True)
        with zipfile.ZipFile(archive,"w") as z: z.writestr("one.csv",b"a"); z.writestr("two.csv",b"b")
        with zipfile.ZipFile(archive) as z: entries=z.infolist(); entries[1].header_offset=entries[0].header_offset
        self.assertIn("ZIP_DUPLICATE_LOCAL_HEADER_OFFSET",w._validate_zip_structure(io.BytesIO(archive.read_bytes()),entries,UploadPolicy({".csv":b""}))); w.close()
    def test_zip_slip_names_are_rejected_before_sandbox_write(self):
        w=self.flow(); policy=UploadPolicy({".csv":b""})
        for name in ("../x.csv", "/x.csv", "C:/x.csv", "\\server\\x.csv", "folder//x.csv", "NUL.csv"):
            with self.assertRaises(ValueError): w.safe_archive_name(name,policy)
        self.assertEqual(w.safe_archive_name("reports/april.csv",policy),"reports/april.csv"); w.close()
    def test_ads_and_windows_filename_bypasses_are_rejected(self):
        w=self.flow(); policy=UploadPolicy({".csv":b""})
        for name in ("file.txt:evil", "file.asax:.jpg", ":stream", " report.csv", "report.csv ", "report.csv.", "CON.txt", "bad|name.csv"):
            with self.assertRaises(ValueError): w.safe_archive_name(name,policy)
        w.close()
    def test_f010_unicode_collision_and_special_entry_are_rejected(self):
        w=self.flow(); policy=UploadPolicy({".csv":b""})
        archive=self.root/"inbox"/"f010.zip"; archive.parent.mkdir(parents=True,exist_ok=True)
        with zipfile.ZipFile(archive,"w") as z:
            z.writestr("café.csv",b"a")
            z.writestr("cafe\u0301.csv",b"b")
            link=zipfile.ZipInfo("link.csv"); link.external_attr=0o120777 << 16; z.writestr(link,b"target")
        reasons=w._inspect_zip_path(archive,policy)
        self.assertIn("ZIP_DUPLICATE_NORMALIZED_PATH",reasons); self.assertIn("ARCHIVE_UNSAFE_ENTRY_TYPE",reasons); w.close()
    def test_f010_invalid_name_and_prefix_confusion_are_rejected(self):
        w=self.flow(); policy=UploadPolicy({".csv":b""})
        with self.assertRaisesRegex(ValueError,"ZIP_INVALID_NAME"): w.safe_archive_name(b"bad.csv",policy)
        archive=self.root/"inbox"/"clean.zip"; archive.parent.mkdir(parents=True,exist_ok=True)
        with zipfile.ZipFile(archive,"w") as z: z.writestr("report.csv",b"id,amount\n1,2\n")
        scanner=type("Scanner",(),{"scan":lambda _,__: ScanResult("clean","test","1")})()
        files=w.extract_zip_safely(archive,self.root/"sandbox",policy,scanner,"../outside")
        self.assertTrue(files[0].is_relative_to((self.root/"sandbox").resolve())); self.assertFalse((self.root/"outside").exists()); w.close()
    def test_f010_ads_archive_quarantines_once_with_evidence_and_alert(self):
        w=self.flow(); archive=self.root/"inbox"/"orders-20260808.csv"; archive.parent.mkdir(parents=True,exist_ok=True)
        with zipfile.ZipFile(archive,"w") as z: z.writestr("file.txt:evil",b"payload")
        scanner=type("Scanner",(),{"scan":lambda _,__: ScanResult("clean","test","1")})()
        policy=UploadPolicy({".csv":b"PK\x03\x04"})
        file_id=w.secure_upload(archive,"vendor","user",policy=policy,scanner=scanner)
        record=w.db.execute("SELECT * FROM file_records WHERE id=?",(file_id,)).fetchone()
        self.assertEqual(record["state"],"security_quarantine"); self.assertTrue(Path(record["quarantine_path"]).exists())
        self.assertEqual(w.db.execute("SELECT count(*) FROM outbox_events WHERE event_type='security.file_upload_quarantined'").fetchone()[0],1)
        retry=self.root/"inbox"/archive.name; retry.write_bytes(Path(record["quarantine_path"]).read_bytes())
        self.assertEqual(w.secure_upload(retry,"vendor","user",policy=policy,scanner=scanner),file_id)
        self.assertEqual(w.db.execute("SELECT count(*) FROM outbox_events WHERE event_type='security.file_upload_quarantined'").fetchone()[0],1); w.close()
    def test_member_scan_failure_cleans_only_generated_sandbox_output(self):
        w=self.flow(); archive=self.root/"inbox"/"clean.zip"; archive.parent.mkdir(parents=True,exist_ok=True)
        with zipfile.ZipFile(archive,"w") as z: z.writestr("report.csv",b"id,amount\n1,2\n")
        with self.assertRaisesRegex(ValueError,"SCAN_NOT_CLEAN"): w.extract_zip_safely(archive,self.root/"sandbox",UploadPolicy({".csv":b""}),type("Scanner",(),{"scan":lambda _,__: ScanResult("error","test","1")})(),"isolated")
        self.assertFalse((self.root/"sandbox"/"isolated").exists()); self.assertTrue(archive.exists()); w.close()

if __name__ == "__main__": unittest.main()
