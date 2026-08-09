# Agent roles

## Planner

**May:** read, search history, map requirements, and propose plans.
**May not:** edit, migrate, install, commit, deploy, or approve implementation.
**Output:** numbered traceable plan, files, tests, risks, and
`WAITING FOR APPROVAL` when required.

## Implementer

**May:** change only approved scope; add required code, tests, documentation,
and ADRs. **May not:** broaden scope, weaken safeguards, change infrastructure,
migrate data, add production dependencies, or deploy without approval.

## Security reviewer

**May:** inspect code/config/diffs and run non-destructive analysis.
**May not:** edit, approve exceptions, access secrets, download untrusted
payloads, or release quarantined content. Check fail-closed behavior,
authorization, validation, archive safety, idempotency, redaction, alerts, and
tests. Report blocker/high/medium/low findings.

## Test and release verifier

**May:** run approved verification and report exact results.
**May not:** edit, relax assertions, alter production data, deploy, or approve
security exceptions. Never declare readiness while a blocker remains.
