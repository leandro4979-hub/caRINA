# ADR-002: Approval-gated SOFA knowledge bridge

## Context

CARINA needs a reusable engineering-knowledge source without granting external
content or a remote service authority over local capabilities. Stack Overflow
for Agents (SOFA) provides authenticated search, post reads, replies, votes,
and verification feedback, but public writes are external side effects and
must not bypass CARINA replay protection, approval, idempotency, or audit.

SOFA also associates authenticated work with short-lived sessions and enforces
read-before-write behavior for contextual interactions. Session recovery must
therefore preserve the read/write relationship rather than blindly retry a
mutation in a fresh session.

## Decision

Add a dedicated `SofaClient` and `SofaContributionAdapter` inside the existing
`CARINAApprovalBoundary` Swift package.

The client is pinned to `https://agents.stackoverflow.com`, receives credentials
through a provider rather than command payloads, creates fresh SOFA sessions as
needed, and retries session-expired reads once. Votes, verifications, and
replies are contextual writes: CARINA reads the target first and, if the SOFA
session expires before the mutation, opens a new session and repeats the read
before retrying the write.

SOFA search and post reads are classified as CARINA read permission. Public
SOFA mutations are classified as execute permission and use the existing
`ProtectedExecutionService`. The contribution adapter requires the approval
card target to exactly equal `sofa:<postID>` so the approved target cannot
silently diverge from the transport target.

Standalone SOFA post creation and SOFA onboarding are excluded from this first
change until their request/credential flows are separately verified.

## Alternatives considered

A generic unrestricted HTTP adapter was rejected because it would broaden the
network authority surface and make host, credential, and mutation policy harder
to audit.

Direct SOFA writes from a model or read client were rejected because they would
bypass CARINA authorization consumption, idempotency reservation, and audit.

Blind retry of a failed write after creating a new SOFA session was rejected
because the new session would not contain the required target read and could
violate SOFA's contextual-write guard.

Persisting SOFA session IDs as credentials was rejected because sessions are
short-lived runtime state, not durable authorization material.

## Consequences

CARINA gains a narrow external engineering-knowledge adapter while retaining
its existing execution boundary. The implementation adds session lifecycle and
network failure modes, and it treats all returned SOFA content as untrusted
input. Public contributions remain user-authorized side effects.

The first version is deliberately incomplete: onboarding and standalone post
publication remain follow-up work. This keeps the API surface constrained to
operations whose current contracts and safety rules are verified.

## Decision summary

Fixed SOFA origin + isolated credential provider + session-aware reads +
read-before-write recovery + existing CARINA approval/idempotency/audit for all
public mutations + fail-closed target binding.
