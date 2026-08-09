# CARINA Approval Boundary

A standalone Swift package implementing the privileged execution boundary:

- deterministic SHA-256 approval fingerprints;
- atomic replay rejection for `(sessionID, sequence, nonce)`;
- expiring, opaque authorization tokens;
- exactly-once token consumption;
- executor-side fingerprint verification immediately before adapter execution;
- a dispatcher that stops at `ApprovalChallenge` and cannot invoke an adapter.
- hash-chained, privacy-minimized approval receipts and dashboard-ready trust snapshots.
- a macOS-only Ollama loopback client with typed health checks and cancellable NDJSON streaming.

Run on macOS with:

```sh
swift test
```

`ReplayProtector` and `AuthorizationTokenVault` are process-local actors. For a
multi-process deployment, preserve their public contracts but replace their
storage with a shared transactional database that provides unique inserts and
atomic compare-and-delete semantics.

`ActionActivityJournal` stores correlation ID, target, fingerprint, terminal
state, UTC timestamp, and a hash chain—never command payloads, credentials,
audio, or model output. Use a protected, append-only filesystem location in a
single-process deployment; use a transactional append-only audit store for
multi-process production deployments.

## Local Ollama (macOS only)

`OllamaClient` connects only to `http://127.0.0.1:11434` by default and uses
`llama3.2:3b`. It performs a short `/api/tags` health check before generation,
then streams `/api/generate` newline-delimited JSON. It has no API key and must
not be included in an iPhone keyboard-extension target: loopback refers to the
device running the code. A future phone-to-Mac connection must be a separately
designed authenticated bridge.
