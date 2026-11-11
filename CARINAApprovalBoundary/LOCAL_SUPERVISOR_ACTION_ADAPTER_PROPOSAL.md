# Engineering Proposal: LocalSupervisorActionAdapter

Status: PROPOSED, NOT AUTHORIZED. No new execution intent, runner grant, or adapter is activated.

## Goal
Allow the local qwen3:8b LangGraph supervisor to propose actions while CARINA alone owns authorization and execution. Model output is always untrusted data, never a shell command or authorization grant.

## Existing contracts
- `PersistentApprovalBoundary.prepare` derives permissions from an immutable capability registry.
- `authorize` issues a short-lived token only after human approval.
- `ProtectedExecutionService.execute` consumes the exact-envelope fingerprint token, reserves idempotency, records an audit event, and only then invokes the adapter.
- AgentRouter `agentrouter-bridge/1` job grants do **not** transport CARINA exact-action tokens. They must not be treated as approval.

## Proposed boundary
1. The supervisor emits a versioned, structured `EngineeringProposal` containing a reviewed intent candidate, explicit target, canonical payload, requested effect, and provenance. Never execute model text.
2. A trusted CARINA component validates schema, type, scope and registry membership, rejecting unknown intents and inputs. Proposed is not authorized, validated is not applied.
3. CARINA presents the **exact** normalized action and target to the human, and uses `PersistentApprovalBoundary.prepare` then `authorize`.
4. Only a trusted adapter host may call `PersistentApprovalBoundary.execute` with the **same envelope** and its issued authorization token. It must not accept a model-supplied token, change request parameters after approval, or fall back to job-level grants.
5. Failures, expiry, changed arguments/target, replay, absent token, or unrecognized capability must result in zero contacts with any external adapter/device/process.
6. Preserve durable, at-most-once invocation and the existing action journal. No automatic retry of a consumed token.

## Explicit exclusions for this proposal
No subprocess/shell access, arbitrary file writes, Appium/WDA interactions, launchd service, network service, new reviewed command-intent registration, or unbounded worker tools. No changes to existing registry permission levels.

## Review gates before implementation or activation
- Review exact proposal schema and allowlisted action catalog separately.
- Decide trusted native Swift IPC and peer authentication without changing AgentRouter v1 semantics.
- Add one deliberately inert adapter interface first; a concrete effectful adapter requires its own capability and exact-action review.
- Verify no token -> zero adapter calls; changed target/payload -> zero calls; expired/replayed token -> zero calls; unknown capability -> zero calls; one matching approved token -> exactly one call.
- Run the CARINA package tests, CI verification, and a separate end-to-end local test before any capability is enabled.

## Regression introduced here
`LocalSupervisorAuthorizationTests.swift` uses the existing `ProtectedExecutionService`, in-memory approval state, and a recording adapter. An unissued token and a valid token for a *different target* both fail before the adapter is invoked. This tests the existing guard, not a not-yet-implemented `LocalSupervisorActionAdapter`.

## Decision
Keep LocalSupervisorActionAdapter proposal-only. Require an independent authorization review before any execution adapter is enabled.
