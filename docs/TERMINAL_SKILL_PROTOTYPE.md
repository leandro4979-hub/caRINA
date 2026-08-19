# caRINA 0.4.0 Terminal Skill Prototype

## Scope

Prototype a visible, tactile skill layer inside the existing macOS terminal
without expanding its execution authority.

## Added skills

- `CODING STANDARDS`: applies the repository coding/security behavior described
  in `CODING_STANDARDS.md` to local Ollama conversations.
- `SECURITY AUDIT`: reproduces an interactive security-audit interview for a
  newly cloud-exposed application or API.

## Acceptance behavior

- The terminal header visibly shows the active skill.
- A **SKILLS** control lists installed skills.
- An **AUDIT** control activates Security Audit mode.
- `/audit` prints the four audit questions: trust-boundary change, ranked
  assets/worst failures, scope, and deliverable.
- `/standards` activates Coding Standards mode.
- `/skill off` returns to general conversation.
- The active skill instructions are included in the local Ollama prompt.
- Up to 12 recent user/caRINA lines, bounded to 8,000 characters, are carried
  forward in memory so an audit interview can continue across turns.
- The terminal still has no shell executor, remote listener, remote fallback,
  deployment authority, secret access, or action-execution bypass.

## Verification status

Repository-side implementation and diff inspection are complete. A macOS Swift
build/run was not executed from the GitHub connector session, so compile and UI
interaction remain **UNVERIFIED** until run locally or by a workflow that builds
`CarinaMacApp`.

Recommended local verification:

```sh
cd CarinaMacApp
swift build
swift run CarinaMacApp
```

Then verify `/skills`, `/audit`, `/standards`, `/skill off`, Command-Return,
Command-Period, active-skill header state, and Ollama streaming.
