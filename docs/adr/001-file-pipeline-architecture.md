# ADR-001: Security-first file pipeline architecture

## Context

The pipeline must safely process independent file deliveries while recovering
from failures and resisting unsafe uploads and archives.

## Decision

Use an explicit state machine with a transactional database as source of truth,
stable file/operation idempotency keys, guarded transitions, durable
checkpoints and leases, reconciliation, audit events, and transactional outbox.
Use restricted quarantine/security-quarantine for failures. Archive extraction
is sandboxed and fail closed; only verified clean extracted members may enter
staging.

For the local vertical slice, SQLite uses WAL and bounded `SQLITE_BUSY`
contention retries. Write transactions are restricted to claims, guarded state
transitions, audit, and outbox updates; hashing, validation, and filesystem I/O
are outside transactions. This is not a distributed-coordination guarantee.

## Alternatives considered

Filesystem-only state, in-memory duplicate locks, best-effort notifications,
and direct archive extraction were rejected because they cannot provide safe
recovery, concurrency control, durable auditability, or a security boundary.

## Consequences

The implementation needs database-backed coordination, outbox relay and
idempotent consumers, scheduled reconciliation, restricted evidence storage,
and a production sandbox/scanner adapter. This adds operational complexity but
prevents ambiguous state from becoming successful processing.

## Decision summary

State machine + database truth + idempotency keys + guarded transitions +
transactional outbox + quarantine + sandboxed archive extraction + fail-closed
security posture.
