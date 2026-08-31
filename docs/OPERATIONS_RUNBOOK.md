# Operations runbook

## Alert routing

Critical alerts page security on-call: malware, suspicious executable, archive
bomb, traversal, or ADS attempt. High alerts create a security ticket and notify
the owner: failed scans, encrypted archives, quarantine thresholds. Medium goes
to security review: unusual types or repeated failures. Low is dashboard/trend
only. Alerts include file ID, source, owner/uploader/IP where allowed, reason,
stage, checksum, quarantine reference, and UTC timestamp—never raw content.

## Operational procedures

- **Missing/late file:** check registry, source, SLA, and prior deliveries;
  alert owner and preserve the audit trail.
- **Stuck job/retry exhaustion:** inspect checkpoint/lease/output intent; run
  reconciliation; set recovery-required rather than guessing success.
- **Failed scan/corruption/quarantine:** restrict access, review manifest and
  report, keep original evidence, and process other files normally.
- **Malware/encrypted archive/bomb/traversal/ADS:** security quarantine,
  critical/high alert as applicable, no automatic release; investigate source.
- **Failed alert delivery:** retain pending outbox event, retry relay, and alert
  operations if delivery age exceeds SLA.
- **CARINA approval mismatch, expiry, or replay:** do not retry or infer
  consent. Show a fresh approval card with the exact target and retain only the
  privacy-minimized receipt. Treat journal-integrity failure as restricted
  audit evidence and fail closed.
- **CARINA capability/version miss:** reject only the affected action before
  payload validation. Put its metadata-only proposal on the restricted review
  queue; do not generate a runtime schema, refresh the registry from the
  request, or retry execution. Continue independent valid batch actions.
- **CARINA locked-plan integrity failure:** do not dispatch. Preserve the
  privacy-minimized correlation ID and integrity reason, mark the action
  failed-before-execution, and require a new request and approval.
- **CARINA restart with pending outbox work:** resume only entries returned by
  the durable ledger and supply their stable dispatch ID to the executor. Do
  not create a new action or change target/parameters. If storage is corrupt or
  the stored plan fails integrity validation, fail closed and escalate.

## CARINA persistent approval recovery

- **Approval database unavailable, corrupt, or locked past timeout:** fail
  closed before challenge issuance or execution. Preserve the existing
  privacy-minimized journal, do not recreate authorization state from UI data,
  and require operator recovery of the protected database.
- **Restart during approval:** reload only the stored challenge/token state.
  Never mint a replacement token from a displayed approval card.
- **Concurrent token presentation:** exactly one transactional delete may win.
  Every loser is treated as consumed/unknown and must not retry execution.
- **Expired replay reservations:** prune only within the configured retention
  transaction. Never remove live reservations to recover capacity.

## Review, recovery, and retention

Only an authorized reviewer may approve a corrected replacement or security
release. Reprocess as a new version with lineage; never blindly replay an
original. Reconciliation is scheduled every 30 minutes and after outages or
deployments. Do not roll back by deleting outputs; use verified recovery or a
recorded compensating action. Restrict evidence access and retain it according
to compliance policy (normally 30–90 days) before approved archival/deletion.

## Dashboard requirements

Track received, processed, duplicates, retries, quarantines,
security-quarantines, missing, late, stuck, scan latency/failures, alert
failures, and reconciliation repairs. Review repeated source failures and
quarantine rates.
