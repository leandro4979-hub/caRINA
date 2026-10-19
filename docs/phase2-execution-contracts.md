# Phase 2 Execution Contracts

## Status

Reference contract only. This document does not enable browser execution and does not alter the Phase 1 deny-only boundary.

## Authority invariant

Only the CARINA Authority Spine may authorize execution. A browser capability may consume an authorization decision, but it must never define the authoritative policy that produces it.

## Native Safari/WebExtension boundary

The dedicated native boundary lives under:

`apps/ios/Carina/SafariExtension/`

The Safari native handler receives extension messages through Apple's `SFExtensionMessageKey` / `NSExtensionContext` mechanism. The handler does **not** accept a complete `EXECUTION_AUTHORIZATION` object from JavaScript. Instead, the browser sends an `EXECUTION_AUTHORIZATION_REQUEST` containing only an authorization ID and the execution context it is asking to use:

- `authorizationId`
- `tabId`
- `frameId`
- `origin`

The native boundary looks up a previously staged authorization and atomically consumes it before returning the authorization to the extension. It validates:

1. message shape and supported request type;
2. authorization lifetime;
3. tab/frame/origin binding;
4. the canonical execution fingerprint;
5. the CARINA authority binding;
6. single-use state.

If any check fails, the authorization is consumed/invalidated and no `EXECUTION_AUTHORIZATION` is returned.

The exact browser entry point is therefore the **response emitted by `SafariWebExtensionHandler.beginRequest(with:)` after `SafariAuthorizationBoundary.consume(...)` succeeds**. That response is the only point at which an already-issued authorization crosses from the native boundary into the Safari extension runtime.

This follows Apple's documented Safari web extension native-messaging model: a background script sends a native message, the native extension handles it in `beginRequest(with:)`, and the native extension returns a response through `SFExtensionMessageKey`.

### Fail-closed authority binding

The native boundary currently uses `UnconfiguredAuthorityBindingVerifier`, which rejects every authorization. This is intentional. The cryptographic issuance and verification semantics for `authorityBinding` have not yet been defined by the CARINA Authority Spine, so the branch cannot accidentally turn a contract-shaped value into execution authority.

A concrete verifier may be introduced only after the Authority Spine specifies the canonical signed/bound input and verification mechanism. The browser/native runtime must never hold a secret that lets it manufacture a valid authority binding.

### Current integration status

The repository's current `main` branch does not contain a Safari Web Extension target. This branch therefore adds the native boundary source and tests as an isolated Phase 2 implementation seam; it does **not** silently modify the Xcode project or create a new extension target. Packaging/wiring the Safari Web Extension target is a separate integration step.

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

`expiresAt` MUST be checked before consumption, and runtime validation MUST require `expiresAt >= issuedAt`. An expired authorization is never executable.

## Result separation

`EXECUTION_RESULT` reports mechanical browser facts only. It MUST NOT establish policy validity or semantic task success. Results are bound to the same tab, frame, and origin context as the authorization.

`VERIFICATION_RESULT` reports observable evidence only. It MUST NOT contain an authoritative success verdict. It is also bound to the authorization's tab, frame, and origin. CARINA evaluates the evidence and records the final semantic verdict in the authority/audit layer.

The browser therefore cannot turn:

```text
"click was dispatched"
```

into:

```text
"the requested intent was successfully completed"
```

## Authority binding

`authorityBinding` is a contract-level SHA-256 value. Its exact canonical input and cryptographic issuance/verification mechanism MUST be defined by the CARINA Authority Spine before execution is enabled. The browser MUST NOT possess any secret required to manufacture a valid authority binding.

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
9. Duplicate or stale result messages that do not match the consumed authorization and execution context.
10. Result messages with undeclared semantic fields such as `success`, `verdict`, or `policyApproved`.

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

The native Swift boundary and JavaScript implementation must be reconciled against these reference contracts before Phase 2 execution is enabled.

## Security boundary

No capability may elevate itself to authority. No browser-originated message may create, extend, reinterpret, or reuse an execution authorization.
