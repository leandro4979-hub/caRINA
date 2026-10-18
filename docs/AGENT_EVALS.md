# Agent configuration evaluations (EVAL-001)

## Scope and acceptance

Every PR receives the stable `agent-evals` check. Changes to root or nested
`AGENTS.md`, `.antigravity/`, tool/schema directories, schema-named files,
CARINA packages, runtime, tests, scripts, workflows or agent/security documents
run both the offline harness and `CARINAApprovalBoundary` Swift test suite.
The `agent-config` label forces evaluation. Merge queues and manual dispatches
always evaluate. Deleted and renamed policy files remain covered.

The aggregate check fails on detection errors, missing outputs, failed,
cancelled or unexpectedly skipped evaluations. A docs-only unrelated change
records an explicit not-applicable success. Workflow-level path filtering is
intentionally absent so required checks are not left pending.

## Activation and ownership

After this workflow lands and a successful check is observed, require the
exact `agent-evals` status in the main-branch ruleset and prevent agent bypass.
This change does not modify branch protection or merge anything. Repository
administration must activate the required status check; adding YAML alone does
not make it mandatory. Preserve any existing required checks when activating.

Protect the workflow, detection logic, eval runner, corpus and policy with
human review. PR-controlled CI can otherwise weaken its own checks. Do not
use pull_request_target, custom secrets or privileged self-hosted runners for
this harness. GitHub-hosted runner egress is not restricted by this workflow.

## Evidence and limits

The artifact includes each offline case's verdict, required/forbidden finding
results and synthetic provenance. Twenty synthetic cases measure plumbing and
regressions, not real reviewer precision. CARINA Swift tests independently
exercise existing authorization, replay, idempotency and audit behavior.
Neither result proves natural-language prompt quality; a future model adapter
and frozen, human-audited real PR cases are needed for that claim.

No CARINA registry, action plan, authorization consumption, reservation,
revocation or durable execution behavior changes. No agent receives write,
approval or merge authority. No model inference occurs or incurs API charges.
GitHub-hosted CI minutes and runner availability remain account-dependent.

## Local verification

Run the check commands in `tools/agent-evals/README.md`, then on a supported
Swift host run `swift test --parallel` in `CARINAApprovalBoundary`. The final
CI result is authoritative for runner-specific checks. Keep production review
in shadow mode until an independently audited corpus supports promotion.
