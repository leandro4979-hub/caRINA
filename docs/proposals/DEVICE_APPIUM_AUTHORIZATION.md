# Engineering proposal: exact-action Appium authorization (NOT IMPLEMENTED)

**Scope:** separate reviewed extension to `CARINAApprovalBoundary`. The merged `tools/ios-wda` smoke test remains manual and must not be exposed as an autonomous command. No change to certificates, Appium service, or device.

## Existing reviewed interfaces (inspected on main)

- `CommandModels.swift`: `CommandIntentID` currently contains `systemStatus`, `workspaceSync`, `sofaContribution`. **No device execution intent exists.**
- `ProductionCommandRouter.permission(for:)` resolves the capability registry and requires an idempotency key for commit/admin actions.
- `CommandDispatcher.dispatch` creates a challenge; the dispatcher never executes privileged operations.
- `PersistentApprovalBoundary.authorize` issues an existing `AuthorizationToken` only after approval.
- `ProtectedExecutionService.execute` computes `ApprovalFingerprint.make(for: envelope)`, consumes the token, reserves the idempotency key, journals the attempt, **then** invokes `AppIntentAdapter.execute`.
- `SQLiteApprovalStateStore` provides durable authorization state; do not invent a second token format or approval database.

## Reviewable implementation design

1. Separately review new **immutable capability-registry** entries and matching `CommandIntentID` cases for narrow device operations, beginning with a non-mutating diagnostic session. Define one exact intent per meaningful operation rather than a generic shell/WebDriver command.
2. Define a canonical payload with a precise device UDID, exact target bundle ID or fixture identifier, operation, permitted arguments, `idempotencyKey`, fixed Appium loopback endpoint and bounded timeout. The approval card must display the effective target and arguments. Never accept an Appium URL, arbitrary WebDriver route, shell command, wildcard app target or unchecked model-supplied operation as a generic execute payload.
3. Create a strictly typed `AppiumDeviceAdapter: AppIntentAdapter` behind an injected local transport protocol. The adapter must receive only the already-approved `CommandRequest` from `ProtectedExecutionService`; the transport must not be accessible from unprotected router paths.
4. Bind approval fingerprints to the exact envelope, intent, payload, target, session identity and nonce using the **existing** `ApprovalFingerprint`. Require one approval per consequent device action. A general test-job approval does not authorize taps, screenshots or app switching.
5. Invoke `PersistentApprovalBoundary.prepare`, obtain explicit human approval via the existing UI, then call `PersistentApprovalBoundary.execute` with the same immutable envelope and issued token. Preserve fail-closed unknown capability handling, token expiry, replay and idempotency checks. No network request should occur until the protected executor invokes the adapter.
6. Keep the default device transport restricted to literal loopback. Never reuse `APPIUM_URL` to bypass approval or connect to a remote service. Add transport timeouts and redact logs/screenshots.

## Required evidence before enabling any autonomous device intent

- No token, expired token, consumed token, wrong device, wrong intent, wrong target, changed payload, unknown capability, duplicate idempotency key: **zero transport calls**, with explicit failure.
- Exact approved command: **one** transport invocation, recorded with the same request fingerprint; replay invokes none.
- Restart and parallel-request tests prove durable token/idempotency state.
- Tests use a recording transport; no actual iPhone, Appium server, or network dependency.
- Separately approved physical-device smoke test only after unit and CI gates pass; no reward-account automation.

## Current disposition

The initial regression test below validates the existing pre-transport protection against a mismatched target using an injected recording adapter. It is a boundary **fixture**, not a real Appium adapter. Full device-intent implementation, review and live execution are deferred. A successful compile/test does **not** prove an autonomous device integration exists.
