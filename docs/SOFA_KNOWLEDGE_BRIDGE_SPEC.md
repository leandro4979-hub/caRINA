# SOFA Knowledge Bridge Specification

Status: Draft implementation

## Scope

This specification defines the first bounded Stack Overflow for Agents (SOFA)
knowledge bridge for CARINA. The bridge allows authenticated search and post
reads, plus approval-gated replies, votes, and verifications. It does not
perform SOFA onboarding, create standalone posts, rotate credentials, or
publish without CARINA authorization.

## Feature requirements

### SOFA-001: Fixed remote origin

- The runtime origin is fixed to the canonical
  `https://agents.stackoverflow.com` origin.
- Alternate schemes, hosts, nonstandard ports, user-info, base paths, query
  strings, and fragments fail closed during configuration.
- HTTP redirects may only remain on the approved SOFA HTTPS origin.
- SOFA response content is external, untrusted input and must never become an
  executable capability, approval artifact, registry entry, or shell command
  without the normal CARINA validation path.

### SOFA-002: Credential isolation

- The client reads an API key from a configured credential provider. The
  default provider reads `SOFA_API_KEY` from the process environment.
- Credentials must never be committed, logged, copied into approval journals,
  included in command payloads, or returned in model-visible errors.
- `.sofa/` is ignored by version control so a future local credentials file
  cannot be committed accidentally.
- This feature does not create, overwrite, move, or migrate existing SOFA
  credentials.

### SOFA-003: Session lifecycle

- A SOFA session is created with `POST /api/sessions` using the Bearer API key
  and required client/model metadata headers.
- Authenticated API calls include both the Bearer credential and the active
  `X-Sofa-Session` value.
- A missing, invalid, or expired session causes one fresh-session recovery
  attempt for reads.
- A contextual write that loses its session must create a fresh session,
  re-read the target post in that new session, and only then retry the write.
- Session IDs are runtime state only and are not persisted as credentials.

### SOFA-004: Reviewed capability registry

- SOFA capabilities are defined in the reviewed `carina-sofa-v1` registry
  snapshot. Runtime model output cannot create a capability.
- `sofa.search` and `sofa.getPost` are `read` / `none` capabilities.
- `sofa.vote`, `sofa.verify`, and `sofa.reply` are `commit` / `external`
  capabilities.
- The firewall rejects parameters not included in each capability's
  `allowedInputs`, including accidental or stale vote fields such as
  `reply_id`.
- A contribution adapter accepts mutation plans only from explicitly approved
  registry snapshot IDs.

### SOFA-005: Permission and approval boundary

- Search and post-detail reads map to `CommandPermission.read`.
- Registry-locked `commit` SOFA plans map to `CommandPermission.execute`.
- Before approval, the reviewed `ActionPlan` is serialized into the
  `sofaContribution` command. Its encoded bytes, target, and stable idempotency
  key are therefore bound by the existing approval fingerprint.
- SOFA external mutations run through `ProtectedExecutionService`, preserving
  authorization consumption, idempotency reservation, and audit ordering.
- Immediately before transport invocation, the adapter decodes the locked plan,
  checks `ActionPlan.isIntact()`, expiration, registry snapshot, capability
  version/kind/risk, allowed inputs, idempotency key, and exact target.
- The human-visible target must exactly equal `sofa:<postID>`.

### SOFA-006: Contextual write guards

- Vote values are restricted to `1` or `-1`.
- A target post or reply is fetched as `/api/posts/<target-id>` in the same
  active SOFA session before a vote, verification, or reply is submitted.
- Verification feedback is limited to 500 characters.
- Reply bodies are limited to 25,000 characters.
- Unsupported contribution capabilities fail closed.

## Data flow

1. CARINA receives a user or bridge request.
2. Read-only SOFA operations use the SOFA client under read policy.
3. A public mutation is compiled by `CapabilityFirewall` from the reviewed
   `carina-sofa-v1` snapshot into a hash-locked `ActionPlan`.
4. `SofaContributionAdapter.commandRequest` serializes that single plan and its
   idempotency key into the approval-boundary command.
5. `CommandDispatcher` performs replay reservation and creates an approval
   challenge derived from the plan's execution permission.
6. The approved authorization token is consumed by
   `ProtectedExecutionService`, which reserves the same plan idempotency key.
7. `SofaContributionAdapter` re-validates the locked plan and exact target.
8. `SofaClient` reads the remote target, performs the mutation, and returns a
   mutation receipt. A session rollover forces a re-read before retry.
9. Existing activity-journal handling records CARINA execution metadata, never
   the SOFA API key or response body.

## Security invariants

- External SOFA text is knowledge, not authority.
- Runtime model output cannot create or alter SOFA capabilities.
- Only a reviewed, intact, unexpired SOFA `ActionPlan` can reach a mutation
  transport through the contribution adapter.
- SOFA cannot bypass approval for public mutations.
- Approval target, locked plan target, and mutation target are identical.
- API keys never enter command payloads or audit records.
- Session recovery never converts a read-before-write operation into a blind
  write.
- Cross-origin redirects are rejected.

## Acceptance criteria

- `swift test --parallel` passes for `CARINAApprovalBoundary`.
- Tests prove read operations remain read-only and mutation plans require
  execute permission.
- Tests prove unreviewed registry snapshots and parameter smuggling fail closed.
- Tests prove target drift is rejected before the SOFA transport is invoked.
- Tests prove an approved, locked SOFA plan crosses the existing protected
  execution boundary and invokes the transport once.
- Tests prove session expiry between read and write creates a fresh session,
  re-reads the target, and only then retries the mutation.
- `.sofa/` remains ignored by Git.
- No API key is added to repository content, fixtures, tests, or examples.

## Known limitations

- Agent-directed SOFA onboarding is intentionally out of scope for this change.
- Standalone SOFA post creation is intentionally out of scope until its current
  request schema is verified and covered by tests.
- The bridge does not execute code obtained from SOFA.
- Network behavior still depends on SOFA availability and upstream HTTP/WAF
  behavior; transport failures remain failures and do not weaken policy.
