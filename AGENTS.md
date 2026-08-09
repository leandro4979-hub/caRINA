# Agent Operating Contract

## Priority order

Apply: explicit user request (unless it conflicts with immutable safety rules),
this file, the nearest nested `AGENTS.md`, Security Requirements, File Pipeline
Specification, relevant ADRs, then existing code conventions. Stop and ask for
a decision if instructions conflict. Never silently weaken security, privacy,
integrity, or auditability.

## Read before work

Before pipeline work, read `docs/FILE_PIPELINE_SPEC.md`,
`docs/SECURITY_REQUIREMENTS.md`, `docs/OPERATIONS_RUNBOOK.md`,
`docs/AGENT_ROLES.md`, `docs/AGENT_CHECKLISTS.md`, relevant ADRs, and the
nearest nested `AGENTS.md`.

## Immutable rules

- Treat uploads, metadata, paths, scanner output, and external events as
  untrusted. Fail closed; do not execute uploaded content.
- Never automatically delete or overwrite originals, expose private files, or
  log contents, credentials, tokens, passwords, or secrets.
- Security failures retain restricted evidence; do not weaken validation,
  sandboxing, scanning, access control, audit, tests, or alerts.
- Database state is authoritative. Use guarded transitions, idempotency keys,
  checkpoints, leases, outbox events, retries, reconciliation, UTC timestamps,
  and per-file isolation.

## Plan-only approval gate

For requests containing `plan first`, `plan only`, `wait for approval`, or
`approval required`: use read-only inspection; do not edit/create/delete/rename
or format files, install packages, change configuration, run migrations,
publish, deploy, or call external write APIs. Return scope, traceability,
files, design, state impact, tests, commands, risks, assumptions, dependencies,
and blocking questions. End exactly with `WAITING FOR APPROVAL`.

Implement only after the user writes exactly:
`Approved: continue implementation.`

## Delivery contract

Implement only approved feature IDs and scope. Update the specification,
security documentation, tests, and ADRs in the same change set. Mark a feature
Complete only after all acceptance criteria and quality checks pass. Final
reports include scope, files, traceability, tests, commands/results, docs/ADRs,
risks, and status recommendation.
