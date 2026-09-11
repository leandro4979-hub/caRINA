# CARINA Browser Automation Milestone BA-001

## Goal

Turn CARINA Skip Assistant into a deterministic, plugin-driven automation engine rather than a generic auto-clicker based on:

`context -> intent -> policy -> verified action`

## Architectural requirements

- SSH keys, GPG keys, API credentials, tokens, and other privileged secrets remain completely outside the browser-automation execution path.
- Browser components never read private keys, receive raw credentials, invoke privileged operations directly, convert denied actions to allowed, bypass safety or policy, or use confidence scores as authorization.
- Plugins provide evidence, candidates, signals, and verification only. They never receive execution or policy authority through registration.
- Unknown policy states fail closed to `DENY`.

## Runtime structure

- `src/core/`: observer, context, intent, scorer, safety, policy, queue, executor, verifier, events, structured logger.
- `src/plugins/`: registry, YouTube, Generic.
- `src/config/`: deterministic defaults.
- `src/index.js`: composition root.
- `tests/browser_automation/`: positive, negative, security, queue, and verification tests.

## Decision pipeline

DOM observation -> context extraction -> plugin candidate discovery -> intent inference -> candidate scoring -> safety classification -> policy decision -> `DENY | APPROVAL_REQUIRED | ALLOW` -> queue only if `ALLOW` -> execute -> verify expected state change -> structured result.

## Sensitive contexts

Autonomous execution is denied for payments, checkout, purchases, financial transfers, login, password entry, passkeys, 2FA, CAPTCHA, account recovery, security settings, permission escalation, credential management, SSH, GPG, API keys, tokens, and wallets.

## Initial plugins

### YouTube

May detect visible site-provided skip controls, playback continuation, and non-sensitive overlays. It must not perform network manipulation, DRM bypass, subscription bypass, authentication bypass, premium spoofing, or anti-automation circumvention.

### Generic

May consider obvious controls such as Skip, Continue, Close, Dismiss, Not now, and Resume, but text matching alone is insufficient. Additional context, score threshold, safety clearance, and policy `ALLOW` are required.

## Queue and verification

- Serialize conflicting actions.
- Prevent duplicate execution.
- Assign stable action IDs within the runtime.
- Support cancellation.
- Reject stale candidates.
- Permit only a small bounded retry for explicitly transient DOM races after policy `ALLOW`.
- Never retry `DENY` or `APPROVAL_REQUIRED` as `ALLOW`.
- Treat success as verified post-action state change, not merely a returned click call.

## Logging and events

Observational events may report scored buttons, proposed actions, executed actions, and verification outcomes. Event listeners do not gain authorization. Structured logs are metadata-only and redact secret-shaped fields.

## Acceptance tests

1. YouTube skip resolves to `ALLOW` and verifies.
2. Low-confidence candidate is denied before execution.
3. Payment context is denied.
4. Login context is denied.
5. Unknown policy state fails closed.
6. `DENY` is not retried or executed.
7. Duplicate actions execute at most once.
8. Verification failure is reported as failure.
9. Credentials and DOM references are excluded from policy proposals.
10. Plugin registration strips execution authority.
11. Generic text matching alone is insufficient.
12. Transient execution retry is bounded and occurs only after `ALLOW`.

## Completion output

Report files changed, architecture decisions, tests and results, assumptions, unresolved risks, and the next milestone: end-to-end Safari/WebExtension integration.
