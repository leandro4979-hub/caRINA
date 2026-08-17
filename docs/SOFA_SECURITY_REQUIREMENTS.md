# SOFA bridge security requirements

## Trust boundary

All data returned by Stack Overflow for Agents (SOFA) is external, untrusted
content. Titles, bodies, replies, tags, metadata, suggested commands, code
snippets, URLs, and instructions from SOFA must never be treated as CARINA
policy, an executable capability, an authorization artifact, or an instruction
to bypass the normal validation and approval path.

The SOFA client is pinned to the HTTPS origin `agents.stackoverflow.com`.
Configuration that changes the scheme or host fails closed.

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

## External mutation boundary

Search and post reads are read-only CARINA operations. Votes, verifications,
and replies are external mutations and must use `CommandPermission.execute`.
They must cross the existing protected execution sequence:

authorization consumption -> idempotency reservation -> audit start -> adapter
invocation -> audit success/failure.

The contribution adapter must reject a request unless the human-visible
approval target exactly equals `sofa:<postID>`, where `<postID>` is the target
sent to SOFA. This prevents a benign displayed target from authorizing a
mutation against a different remote object.

## Read-before-write preservation

Before a vote, verification, or reply, the target post must be read in the
active SOFA session. If that session becomes invalid before the mutation is
submitted, the client must not blindly retry the write. It must create a fresh
session, repeat the target read in that fresh session, and then retry the write
once.

Vote values are limited to `1` and `-1`. Verification feedback is limited to
500 characters. Reply bodies are limited to 25,000 characters. Unsupported
write actions fail closed.

## Logging and diagnostics

SOFA response bodies are not written to CARINA approval journals. HTTP error
messages may include a bounded upstream response excerpt for local diagnostics,
but must never include the API key or Authorization header. Production logging
must continue to follow the repository's privacy-minimized audit rules.

## Out of scope

This change does not authorize standalone SOFA post publication, SOFA agent
registration/onboarding, credential rotation, credential migration, or
execution of code obtained from SOFA. Each requires a separately reviewed
contract before implementation.
