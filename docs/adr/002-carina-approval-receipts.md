# ADR-002: CARINA approval receipts and trust state

## Decision

CARINA records the approval lifecycle in an append-only, hash-chained,
privacy-minimized journal. The original request correlation ID survives
preparation, user decision, invocation, and outcome. Approval fingerprints
bind the exact target and canonical payload; tokens expire and consume before
execution.

Executable capabilities are compiled only from an immutable deployment
snapshot keyed by `(capability_id, version_major)`. The ActionPlan is a locked
artifact: the registry identity, normalized parameters, target, user/device,
preflight state, expiry, nonce, and idempotency key are deterministically
hashed. The ledger checks that hash before each state transition. Batch
compilation uses independent results: valid actions continue, while unknown or
mismatched capabilities become metadata-only DLQ proposals that have no
execution interface.

DLQ proposals retain only review-safe metadata and hashes of untrusted intent
or suggested schema material. Strict per-item batch and payload limits prevent
one excessive proposal from consuming the entire batch or exposing its content.

## Persistent runtime extension

The production command composition root uses the reviewed capability registry
to derive read, preparation, or execution permission. It shares one SQLite
store across replay protection, approval verification, and executor
idempotency reservation. Unique inserts and transactional token deletion
survive restart and prevent two cooperating processes from consuming the same
authority. The macOS app still exposes no privileged action adapter; adding one
requires a separately reviewed capability and adapter implementation.

## Consequences

Changed targets, replay, expiry, or journal-integrity failure fail closed and
require a new decision. The local JSON-lines journal is suitable only for a
single process; multi-process production requires equivalent transactional
append and atomic compare-and-delete semantics.

The current implementation intentionally does not claim multi-process
distributed durability, cryptographic identity attestation, or an external DLQ
transport. A local durable ledger/outbox provides same-host advisory-lock and
atomic-replace recovery, but deployment still requires a transactional database,
segregated IAM roles, and idempotent delivery workers.
