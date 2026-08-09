# caRINA

caRINA is Leandro's local AgentOps dashboard project and engineering codex.

## Dashboard

Build and verify the local dashboard:

```sh
make verify
```

The dashboard reads AgentOps Markdown notes and writes `dist/dashboard.html`.

## Codex

| Section | Purpose |
| --- | --- |
| [Glossary](glossary.md) | Definitions of key terms |
| [Snippets](snippets/README.md) | Reusable, runnable code by language |
| [Patterns](patterns/README.md) | Architectural patterns and tradeoffs |
| [Shortcuts](shortcuts/README.md) | Keyboard, terminal, and IDE productivity |
| [Tools](tools/git-basics.md) | Development tooling references |
| [GitHub CLI](tools/github-cli.md) | Authentication, pull requests, and CI inspection |

## Development

Run `make verify` before committing. Commit source and documentation changes, not generated dashboard output. See [CONTRIBUTING.md](CONTRIBUTING.md) for project and codex conventions.

## File workflow

`src/file_workflow.py` is a local, rule-driven intake workflow. SQLite is its
durable source of truth: it stores file versions, uniquely claimed operations,
guarded state transitions, move intents, audit events, idempotent result
writes, and a transactional outbox. Valid files move through `inbox`,
`staging`, `processing`, `complete`, and `archive`; unknown or invalid files
move to `quarantine`. Existing destination files are checksum-verified and are
never overwritten.

A file version has a deterministic identity of
`SHA-256(source_id + source_key + content_checksum)`. Thus the same delivery
returns the stored result, while the same source filename/key with changed
content becomes a new version. Different source keys with identical bytes are
deliberately separate business files.

Copy and adapt `config.workflow.example.json`, then run:

```sh
python3 src/file_workflow.py /path/to/workflow-root config.workflow.json
python3 src/file_workflow.py /path/to/workflow-root config.workflow.json --reconcile
```

Run reconciliation every 30 minutes with your scheduler. It verifies and marks
completed interrupted moves, and reports expired leases and unsafe missing
moves. A host integration should call `relay_outbox(publisher)` until no
pending events remain; consumers must deduplicate by `event_key`. Recover a
quarantined file by correcting a *copy* and placing it back in `inbox`; retain
the quarantined original for investigation.

Jobs persist checkpoints from `claimed` through `event_queued`. Validation
errors are permanent and quarantine the file; storage/timeout errors use the
1/5/15-minute retry policy; crashes, expired leases, and conflicting or
incomplete moves enter `recovery_required`. Reconciliation only promotes a
temporary or final file after its checksum matches the recorded move intent.

Quarantine is isolated per file version. It copies evidence to
`quarantine/source=<source>/date=<UTC-date>/file_id=<id>/`, retaining an
immutable `original.bin`, manifest, and validation report without deleting the
source. Reprocessing requires an explicit approval flag, uses a replacement
copy, creates a new version, and retains the original quarantine lineage.

For untrusted uploads, use `Workflow.secure_upload()` rather than `ingest()`.
It accepts files only from the private inbox and blocks them until allowlist,
filename, size, magic-byte, hash, ZIP-limit, and malware checks are clean.
`FailClosedScanner` intentionally blocks every upload until a production
scanner adapter is supplied. Security alerts are transactional outbox events
containing metadata and hashes only—never the raw file. `security_release()`
requires explicit approval and always rescans the immutable evidence copy.

ZIP signatures receive metadata-only preflight inspection before any
extraction. The configurable policy rejects encrypted, malformed, traversing,
duplicate-path, symlink, over-expanded, over-compressed, oversized, or overly
nested archives. There is no password-handling exception in this local tool;
encrypted archives remain quarantined. A production sandbox adapter is still
required before clean archive contents can be released to staging.

Preflight applies per-entry and total compression-ratio limits, checks ZIP
local-header offsets and Zip64 policy, and has a parse-time limit. The optional
`extract_zip_safely()` helper repeats expansion, path, type, and wall-clock
checks while writing only within a caller-provided sandbox; it does not release
the original archive to the pipeline.

ZIP preflight independently validates each central-directory entry against its
local header. Duplicate/out-of-range offsets, invalid signatures, header
mismatches, duplicate normalized paths, and overlapping compressed-data ranges
are treated as malformed security failures and remain quarantined.

Archive member names are strict relative POSIX paths. Backslashes, absolute or
drive/UNC paths, traversal segments, repeated separators, control characters,
reserved Windows device names, excessive depth, and case-folded collisions are
rejected in both preflight and immediately before exclusive sandbox writes.
Colon/ADS forms, other Windows-forbidden characters, and trailing dots or
spaces are also rejected. Extracted files use server-generated entry IDs;
archive member names remain metadata only and cannot influence output paths.

For transient processing work, call `Workflow.schedule_retry(file_id, error)`;
it returns the required 1, 5, and 15 minute delays, then quarantines the file.
