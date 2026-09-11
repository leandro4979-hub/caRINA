# Phase 2 Execution Contracts

## Status

Reference contract only. This document does not enable browser execution and does not alter the Phase 1 deny-only boundary.

## Authority invariant

Only the CARINA Authority Spine may authorize execution. A browser capability may consume an authorization decision, but it must never define the authoritative policy that produces it.

## Execution state machine

```text
ISSUED
  |
  | atomic consume()
  v
CONSUMED
  |
  v
EXECUTING
  |             \
  v              v
COMPLETED      FAILED
```

There is no transition from `CONSUMED`, `EXECUTING`, `COMPLETED`, or `FAILED` back to `ISSUED`.

Authorization MUST be atomically consumed before target resolution or action dispatch. The consume operation MUST be serialized or otherwise atomic so concurrent requests cannot both obtain execution rights.

## Authorization binding

`EXECUTION_AUTHORIZATION` binds the exact execution context:

- `authorizationId`
- `requestId`
- `nonce`
- `candidateId`
- `pluginId`
- `intent`
- `action`
- `tabId`
- `frameId`
- `origin`
- `issuedAt`
- `expiresAt`
- `executionFingerprint`
- `authorityBinding`

The `executionFingerprint` is the canonical SHA-256 digest of the execution tuple. Any change to a bound field invalidates the authorization.

`expiresAt` MUST be checked before consumption. An expired authorization is never executable.

## Result separation

`EXECUTION_RESULT` reports mechanical browser facts only. It MUST NOT establish policy validity or semantic task success.

`VERIFICATION_RESULT` reports observable evidence only. It MUST NOT contain an authoritative success verdict. CARINA evaluates the evidence and records the final semantic verdict in the authority/audit layer.

The browser therefore cannot turn:

```text
"click was dispatched"
```

into:

```text
"the requested intent was successfully completed"
```

## Required replay defenses

The implementation must reject:

1. Reuse of the same authorization after successful consumption.
2. Concurrent attempts to consume the same authorization.
3. Expired authorizations.
4. Authorizations presented for another tab or frame.
5. Authorizations presented for another origin.
6. Authorizations whose candidate, plugin, intent, or action differs from the bound fingerprint.
7. Unknown or malformed authorization IDs.
8. Browser-originated attempts to mint or extend authorization.
9. Duplicate or stale result messages that do not match the consumed authorization.

## Phase 1 compatibility

The existing BA-001 background boundary remains deny-only. Until Phase 2 execution code is separately implemented and verified, any native response other than `DENY` remains rejected by the Phase 1 path.

No Phase 2 schema alone grants execution authority.

## Contract definitions

The normative machine-readable definitions are in:

`schemas/phase2-execution-contracts.v1.json`

The schema defines:

- `EXECUTION_AUTHORIZATION`
- `EXECUTION_RESULT`
- `VERIFICATION_RESULT`

The native Swift handler and JavaScript implementation must be reconciled against these reference contracts before Phase 2 execution is enabled.

## Security boundary

No capability may elevate itself to authority. No browser-originated message may create, extend, reinterpret, or reuse an execution authorization.
