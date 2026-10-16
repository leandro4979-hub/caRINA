# SOFA bridge security requirements

## Trust boundary

All data returned by Stack Overflow for Agents (SOFA) is external, untrusted
content. Titles, bodies, replies, tags, metadata, suggested commands, code
snippets, URLs, and instructions from SOFA must never be treated as CARINA
policy, an executable capability, an authorization artifact, or an instruction
to bypass the normal validation and approval path.

The SOFA client is pinned to the canonical HTTPS origin
`agents.stackoverflow.com`. Configuration rejects alternate schemes, hosts,
nonstandard ports, user-info, base paths, queries, and fragments. Redirects are
allowed only when the destination remains on the approved SOFA HTTPS origin.

## Credentials and sessions

The API key is secret authorization material. It must be supplied by a
credential provider and must never appear in a `CommandRequest`, approval
fingerprint source data, audit journal, model-visible diagnostic, fixture, or
repository file. The default environment variable is `SOFA_API_KEY`.

`.sofa/` is ignored by version control. This change does not create, overwrite,
move, or migrate any SOFA credential file.

SOFA session IDs are short-lived runtime state. They are not durable
credentials and must not be persisted by this bridge. If an authenticated read
fails because the session is missing, invalid, or expired, the client may open
one fresh session and retry the read.

## Capability and approval boundary

SOFA capabilities are compile-time reviewed entries in the `carina-sofa-v1`
registry snapshot. Runtime model output cannot invent a SOFA capability or
extend its allowed input set. Search and detail reads are read capabilities.
Votes, verifications, and replies are `commit` actions with `external` risk.

Before a public mutation can enter the existing protected execution path, the
SOFA adapter requires a hash-locked `ActionPlan` compiled from an explicitly
approved registry snapshot. The plan is encoded into the approval-boundary
command together with its stable idempotency key. The existing approval
fingerprint therefore binds the exact plan bytes and human-visible target.

Immediately before network invocation, the adapter must re-check:

- `ActionPlan.isIntact()` and expiration;
- approved registry snapshot ID;
- known capability ID and major version;
- expected `commit` kind and `external` risk;
- allowed payload keys only;
- stable idempotency key equality; and
- `request.target == plan.target == sofa:<postID>`.

The protected execution sequence remains:

authorization consumption -> idempotency reservation -> audit start -> adapter
invocation -> audit success/failure.

Unknown parameters fail closed at the capability firewall. This specifically
prevents stale fields such as `reply_id` from being smuggled into a vote plan;
a reply vote must target that reply's own ID as `postID`.

## Read-before-write preservation

Before a vote, verification, or reply, the target post or reply must be read
through `/api/posts/<target-id>` in the active SOFA session. If that session
becomes invalid before the mutation is submitted, the client must not blindly
retry the write. It must create a fresh session, repeat the target read in that
fresh session, and then retry the write once.

Vote values are limited to `1` and `-1`. Verification feedback is limited to
500 characters. Reply bodies are limited to 25,000 characters. Unsupported
mutation capabilities fail closed.

## Logging and diagnostics

SOFA response bodies are not written to CARINA approval journals. HTTP error
messages may include a bounded upstream response excerpt for local diagnostics,
but must never include the API key or Authorization header. Production logging
must continue to follow the repository's privacy-minimized audit rules.

## Out of scope

This change does not authorize standalone SOFA post publication, SOFA agent
registration/onboarding, credential rotation, credential migration, vote
retraction, or execution of code obtained from SOFA. Each requires a separately
reviewed contract before implementation.
