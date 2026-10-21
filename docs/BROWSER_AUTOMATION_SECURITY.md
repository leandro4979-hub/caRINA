# CARINA Browser Automation Security Requirements

## Boundary

The browser automation runtime is an unprivileged decision and DOM-interaction layer. It must not import, read, receive, log, or persist SSH private keys, GPG private keys, API credentials, authentication tokens, cookies, password values, wallet material, or other privileged secrets.

Browser plugins are untrusted evidence providers. Registration exposes only `id`, `hosts`, `detect`, `candidates`, `signals`, and `verify`. Extra plugin properties, including execution helpers, are not copied into the registered plugin facade.

## Authorization

Confidence is evidence, not permission. Every executable candidate passes through the safety classifier and injected policy engine. The only executable terminal policy state is `ALLOW`.

- `DENY`: do not queue, execute, or retry.
- `APPROVAL_REQUIRED`: do not queue or execute. A separately reviewed approval flow must produce a fresh authorized decision.
- Unknown or malformed policy state: fail closed as `DENY` with `UNKNOWN_POLICY_STATE`.
- Missing policy engine: fail closed.

## Sensitive contexts

Autonomous browser execution is denied when page or candidate context indicates payments, checkout, purchases, financial transfers, login, password entry, passkeys, 2FA, CAPTCHA, account recovery, security settings, permission escalation, credential management, SSH, GPG, API keys, tokens, or wallets.

## Data minimization

Policy proposals contain only sanitized metadata required for a decision: candidate ID, plugin ID, inferred intent, confidence and reason codes, host/path, coarse media/overlay state, and sensitive classification. Raw DOM elements, field values, cookies, storage, credentials, and arbitrary page text are excluded.

Structured logging applies key-based redaction and must never be used to serialize raw candidate objects or page DOM.

## Execution and verification

Execution occurs only after `ALLOW`. The queue provides duplicate suppression, cancellation, serialization, stale-candidate rejection in the composition root, and bounded retries only for errors explicitly marked transient. Policy denials are never retried.

A completed DOM method call is not proof of success. Each plugin supplies a post-action verifier. Failed verification is reported as failure and must not be upgraded to success by fallback logic.

## Site behavior limits

The initial YouTube plugin operates only through site-provided visible DOM controls. It does not rewrite network requests, evade advertising systems, bypass DRM, spoof subscriptions, bypass authentication, or defeat anti-automation protections.
