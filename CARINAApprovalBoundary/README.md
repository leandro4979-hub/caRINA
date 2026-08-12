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

The validator exposes `revalidateFilesystemState(_:)`, but the executor must call it immediately before consuming the single-use authorization and performing the mutation. This keeps validation evidence attached to the exact filesystem state that was approved.
