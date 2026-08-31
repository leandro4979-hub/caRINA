# Security requirements

## Upload boundary

Uploads enter only private, non-public inbox/staging. Permit configured types
only; validate server-side extension, declared MIME, magic bytes, size,
stability, SHA-256, uploader/source provenance, and malware scan. Scan errors
fail closed. Never execute upload content. Alerts contain metadata and hashes,
never raw attachments; rate-limit and trend-alert by source, uploader, IP, and
vendor.

## Corrupt-file evidence and quarantine (F-001–F-004)

Normal quarantine is for corrupt, malformed, or invalid business input.
Security quarantine is restricted to unsafe or suspicious input; a corrupt CSV
is not automatically a security incident. Each quarantine event has exactly
one primary machine-readable reason code and may have secondary codes. Required
codes are `FILE_CORRUPT_CRC_MISMATCH`, `FILE_CORRUPT_TRUNCATED`,
`FILE_CORRUPT_CHECKSUM_MISMATCH`, `FILE_FORMAT_MALFORMED`,
`FILE_VALIDATION_SCHEMA_FAILURE`, `PIPELINE_VALIDATION_INTERNAL_ERROR`, and
`PIPELINE_UNKNOWN_VALIDATION_FAILURE`.

Evidence uses server-generated storage IDs, never supplied paths or names.
The original, manifest, and validation report each have an immutable SHA-256.
Access class, retention date, and legal-hold state are durable metadata.
Reprocess and purge require authorization and append-only audit events;
reconciliation must never purge, overwrite, relabel, or otherwise mutate source
evidence.

## Archive policy

Detect archive types from signatures. Default-deny encrypted/password-protected
archives unless a separately approved password/secrets workflow exists.
Preflight before extraction; enforce limits for compressed/expanded sizes,
single entry, count, ratio, nesting, parser/extraction time, CPU, memory, disk,
and process count. Metadata is insufficient: enforce actual-byte limits in a
non-root, no-network, temporary isolated sandbox with read-only application
filesystem and cleanup. Reject bombs, malformed/ambiguous archives, Zip64
unless enabled, unsafe nesting/types/paths, duplicate offsets, and overlapping
ranges. Scan and true-type validate each member; release only clean extracted
members to staging.

## ZIP path policy

Treat member paths as POSIX. `/` is only a segment separator; reject `\`,
absolute/drive/UNC paths, empty/`.`/`..` segments, null/control data, invalid
encoding, excessive length/depth, links/special files, and duplicate normalized
paths. Resolve generated targets canonically under sandbox root immediately
before exclusive creation. Never bulk extract or use an archive member name as
a physical destination.

## NTFS ADS and Windows-safe names (F-010)

Strictly decode and NFC-normalize each member. Reject a colon in every segment,
including `file.txt:evil`, `file.asax:.jpg`, and `:stream`, as
`ARCHIVE_NTFS_ADS_NAME`. Reject `< > : " \ | ? *`, trailing spaces/periods,
and reserved names (CON, PRN, AUX, NUL, COM1–COM9, LPT1–LPT9, including
extensions). Detect normalized/case-folded collisions. Never sanitize and
continue: quarantine the archive with immutable evidence, audit, and a
deduplicated alert. Use generated file-ID/entry-index paths and preserve member
names only as metadata. Where NTFS storage is used, verify no named streams
exist before release.

**F-010 verification:** complete on 2026-08-08; see the F-010 verification
record in `FILE_PIPELINE_SPEC.md`.

## CARINA approval receipts (AUD-001–AUD-004)

Approval audit storage is append-only and hash chained. Store only correlation
ID, fingerprint, displayed target, state, and UTC time; never raw payload
contents, audio, credentials, or model responses. Verify journal integrity
before loading persisted history and fail closed on tampering. Multi-process
production deployments require a protected transactional append-only store;
the package journal is limited to single-process local use.

## CARINA capability allowlist and approval artifacts (AUD-005, AUD-006, AUD-008)

Only a reviewed, deployment-time registry snapshot may supply executable
capabilities. The lookup key is capability ID plus major version; a key miss is
a hard denial before dynamic validation, schema construction, or execution.
LLM output may propose an intent and values, but may never create, update, or
select an unreviewed capability contract.

Approval operates on one locked `ActionPlan`, not the original request. Its
integrity hash includes the registry snapshot, capability version, normalized
parameters, target, user/device, preflight evidence, expiry, nonce, and
idempotency key. The ledger validates the hash at every guarded transition,
preventing changed-target or changed-parameter reuse. Failed capability
proposals are metadata-only DLQ records. Their reviewer must not hold
action-execution or registry-promotion authority.

DLQ records must exclude raw intent, payloads, suggested schema text, voice,
credentials, and model output. The package stores one-way hashes for review
deduplication and correlation only. Oversized payloads and over-limit batch
entries fail per item into the same privacy-minimized policy-rejection path.

## CARINA persistent approval runtime (AUD-009)

Production command routing derives permission only from the immutable capability
registry snapshot. Unknown capabilities, versions, inputs, accounts, and
recipient limits fail before replay reservation or challenge creation.

Replay tuples, approval challenges, authorization tokens, and executor
idempotency keys share one SQLite authority. Unique constraints and
`BEGIN IMMEDIATE` transactions enforce atomic reservation and token
compare-and-delete across app restarts and cooperating same-host processes.
SQLite runs in WAL mode with full synchronization and a bounded busy timeout.
The database stores no raw model text, credentials, audio, or response content.
Database open, schema, lock, corruption, and write failures fail closed.

## CARINA durable ledger and outbox (AUD-007)

The local durable ledger holds an advisory process lock while it loads,
validates, changes, and atomically replaces its store. It writes reservation,
idempotency mapping, and outbox entry together. A stored plan is verified again
before it is returned for dispatch; any corrupt store or hash mismatch fails
closed. Dispatch uses the stable outbox ID as its downstream idempotency key,
and completion atomically terminates both the ledger and outbox record.

This provides a tested same-host reference boundary, not a distributed
consensus or trusted-storage guarantee. Production must use a transactional
database/outbox, protected storage, reconciliation, and separately authorized
delivery workers.
