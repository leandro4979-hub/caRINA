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

- The runtime origin is fixed to `https://agents.stackoverflow.com`.
- Alternate schemes or hosts fail closed during configuration.
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
  and client/model metadata headers.
- Authenticated API calls include both the Bearer credential and the active
  `X-Sofa-Session` value.
- A missing, invalid, or expired session causes one fresh-session recovery
  attempt for reads.
- A contextual write that loses its session must create a fresh session,
  re-read the target post in that new session, and only then retry the write.
- Session IDs are runtime state only and are not persisted as credentials.

### SOFA-004: Permission and approval boundary

- Search and post-detail reads map to `CommandPermission.read`.
- Reply, vote, and verification operations map to `CommandPermission.execute`.
- SOFA external mutations run through the existing `ProtectedExecutionService`
  so authorization consumption, idempotency reservation, and audit ordering are
  preserved.
- The approved human-visible target must exactly equal `sofa:<postID>` before a
  contribution adapter can invoke the transport. Target/payload drift fails
  closed.
- Every protected SOFA mutation requires a non-empty idempotency key through the
  existing execution boundary.

### SOFA-005: Contextual write guards

- Vote values are restricted to `1` or `-1`.
- A target post is read in the same active SOFA session before a vote,
  verification, or reply is submitted.
- Verification feedback is limited to 500 characters.
- Reply bodies are limited to 25,000 characters.
- Unsupported contribution actions fail closed.

## Data flow

1. CARINA receives a user or bridge request.
2. Read-only SOFA operations use the SOFA client directly under read policy.
3. Public mutations are represented as `sofaContribution` commands.
4. `CommandDispatcher` performs replay reservation and creates an approval
   challenge for execute permission.
5. The approved authorization token is consumed by
   `ProtectedExecutionService`.
6. The service reserves the idempotency key and records execution start.
7. `SofaContributionAdapter` validates the exact target and typed operation.
8. `SofaClient` reads the remote target, performs the mutation, and returns a
   mutation receipt.
9. Existing activity-journal success/failure handling records only CARINA
   execution metadata, never the SOFA API key or response body.

## Security invariants

- External SOFA text is knowledge, not authority.
- SOFA cannot create or select CARINA capabilities.
- SOFA cannot bypass approval for public mutations.
- Approval target and mutation target are identical.
- API keys never enter command payloads or audit records.
- Session recovery never converts a read-before-write operation into a blind
  write.
- No SOFA endpoint may be redirected to a non-approved origin by configuration.

## Acceptance criteria

- `swift test --parallel` passes for `CARINAApprovalBoundary`.
- Tests prove read operations remain read-only and contribution operations map
  to execute permission.
- Tests prove target drift is rejected before the SOFA transport is invoked.
- Tests prove an approved SOFA mutation crosses the existing protected
  execution boundary and invokes the transport once.
- `.sofa/` remains ignored by Git.
- No API key is added to repository content, fixtures, tests, or examples.

## Known limitations

- Agent-directed SOFA onboarding is intentionally out of scope for this change.
- Standalone SOFA post creation is intentionally out of scope until its current
  request schema is verified and covered by tests.
- The bridge does not execute code obtained from SOFA.
- Network behavior still depends on SOFA availability and upstream HTTP/WAF
  behavior; transport failures remain failures and do not weaken policy.
