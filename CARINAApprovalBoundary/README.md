# CARINA Approval Boundary

This Swift package isolates CARINA's authorization and execution boundary from the rest of the app.

The boundary is fail-closed and intentionally separates untrusted intent from execution authority.

## Existing control-plane guarantees

- typed command envelopes
- replay protection and idempotency
- approval fingerprints
- durable action journaling
- execution boundary adapters
- local Ollama integration
- effect-verified revocation with stale-gateway fencing

## Effect-verified revocation

`RevocationOutcomeMonitor` treats receiver persistence, gateway installation,
and independent effect observation as separate evidence. A gateway without a
fresh receipt is fenced, and completion requires every gateway in the frozen
population to have both a current receipt and a no-committed-effect observation
after the window closes. Any committed effect makes the violation sticky.

The monitor is an in-memory reference boundary. Distributed deployments must
persist and authenticate its evidence transactionally and must not infer
enforcement from delivery acknowledgement alone.

## Proposal validation keel

Engineering proposals now pass through a strict validation chain before they can become execution candidates:

1. Raw Git-style unified diff text is quarantined in `DiffMutationInspector`.
2. Only pre-hunk metadata is structural; hunk contents are opaque data.
3. Declared mutations and observed mutations are canonicalized and reconciled.
4. Repository scope and protection tiers come from the CARINA registry, never from proposal claims.
5. Expected filesystem state is captured for every affected source or destination.
6. The authority fingerprint uses a fixed-order, length-prefixed byte representation instead of JSON serialization.
7. The fingerprint binds proposal identity, tool and registry versions, canonical repo root, sorted mutations, filesystem state, and a normalized diff digest.
8. Filesystem state must be revalidated immediately before an execution authorization is consumed.

## Filesystem state binding

Existing files are bound by canonical path, device, inode, content SHA-256, and parent directory identity. Create destinations are required to remain absent and are bound to parent directory identity. Rename operations bind both the existing source and the absent destination.

Symlinks, missing expected paths, unexpected destinations, unsupported object types, and changed state fail closed.

## Remaining execution integration

The validator exposes `revalidateFilesystemState(_:)`. The executor must call it immediately before consuming the single-use authorization, reserve idempotency only after that revalidation succeeds, then perform the mutation and verify the result. This keeps approval evidence attached to the exact filesystem state that was approved.
