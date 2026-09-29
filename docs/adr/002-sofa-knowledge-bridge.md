# ADR-002: Approval-gated SOFA knowledge bridge

## Context

CARINA needs a reusable engineering-knowledge source without granting external
content or a remote service authority over local capabilities. Stack Overflow
for Agents (SOFA) provides authenticated search, post reads, replies, votes,
and verification feedback, but public writes are external side effects and
must not bypass CARINA registry policy, replay protection, approval,
idempotency, or audit.

SOFA also associates authenticated work with short-lived sessions and enforces
read-before-write behavior for contextual interactions. Session recovery must
therefore preserve the read/write relationship rather than blindly retry a
mutation in a fresh session.

## Decision

Add a dedicated `SofaClient`, reviewed `SofaCapabilityCatalog`, and
`SofaContributionAdapter` inside the existing `CARINAApprovalBoundary` Swift
package.

The client is pinned to the canonical `https://agents.stackoverflow.com`
origin, rejects cross-origin redirects, receives credentials through a provider
rather than command payloads, creates fresh SOFA sessions as needed, and
retries session-expired reads once. Votes, verifications, and replies are
contextual writes: CARINA reads the target first and, if the SOFA session
expires before mutation, opens a new session and repeats the read before
retrying the write.

SOFA capabilities are compile-time reviewed in the `carina-sofa-v1` registry
snapshot. Search and post reads are `read` capabilities. Vote, verification,
and reply are `commit` capabilities with `external` risk. Unknown inputs fail at
the capability firewall.

A public mutation must be represented by a hash-locked `ActionPlan` produced
from an approved registry snapshot. `SofaContributionAdapter.commandRequest`
serializes that one locked plan and its stable idempotency key into the existing
approval-boundary command. The approval fingerprint therefore binds the exact
plan bytes and human-visible target. Immediately before transport invocation,
the adapter re-validates plan integrity, expiration, snapshot, capability
version/kind/risk, allowed inputs, idempotency key, and exact
`sofa:<postID>` target.

The resulting command uses the existing `ProtectedExecutionService`, retaining
authorization-token consumption, idempotency reservation, and audit ordering.

Standalone SOFA post creation and SOFA onboarding are excluded from this first
change until their request and credential flows are separately verified.

## Alternatives considered

A generic unrestricted HTTP adapter was rejected because it would broaden the
network authority surface and make host, credential, and mutation policy harder
to audit.

Loose action strings such as `action=vote` were rejected for mutation dispatch
because caller-supplied text could drift from registry-derived policy. Locked
`ActionPlan` artifacts preserve the reviewed capability identity and payload.

Direct SOFA writes from a model or read client were rejected because they would
bypass CARINA authorization consumption, idempotency reservation, and audit.

Blind retry of a failed write after creating a new SOFA session was rejected
because the new session would not contain the required target read and could
violate SOFA's contextual-write guard.

Allowing arbitrary redirects was rejected because a pinned starting URL alone
does not guarantee that credentials or mutation payloads remain on the reviewed
origin.

Persisting SOFA session IDs as credentials was rejected because sessions are
short-lived runtime state, not durable authorization material.

## Consequences

CARINA gains a narrow external engineering-knowledge adapter while retaining
its existing registry and execution boundaries. The implementation adds session
lifecycle and network failure modes, and all returned SOFA content remains
untrusted input. Public contributions remain user-authorized side effects.

The first version is deliberately incomplete: onboarding, standalone post
publication, and vote retraction remain follow-up work. This keeps the API
surface constrained to operations whose current contracts and safety rules are
verified.

## Decision summary

Canonical SOFA origin + cross-origin redirect rejection + isolated credential
provider + reviewed capability registry + locked `ActionPlan` mutation
artifacts + session-aware read-before-write recovery + existing CARINA
approval/idempotency/audit + fail-closed target binding.
