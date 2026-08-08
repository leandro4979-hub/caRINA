# CARINA Approval Boundary

A standalone Swift package implementing the privileged execution boundary:

- deterministic SHA-256 approval fingerprints;
- atomic replay rejection for `(sessionID, sequence, nonce)`;
- expiring, opaque authorization tokens;
- exactly-once token consumption;
- executor-side fingerprint verification immediately before adapter execution;
- a dispatcher that stops at `ApprovalChallenge` and cannot invoke an adapter.

Run on macOS with:

```sh
swift test
```

`ReplayProtector` and `AuthorizationTokenVault` are process-local actors. For a
multi-process deployment, preserve their public contracts but replace their
storage with a shared transactional database that provides unique inserts and
atomic compare-and-delete semantics.
