# ADR 003: Require evidence for agent configuration changes

Status: Proposed in EVAL-001.

## Decision

Use an always-reported `agent-evals` aggregate check with internal changed-path
detection. Applicable changes require offline harness results and the existing
CARINA approval-boundary regression suite. Isolate the zero-dependency Node
harness under `tools/agent-evals`; leave runtime authorization code unchanged.

## Consequences

Unrelated changes explicitly pass as not applicable. Missing detection or test
evidence fails the aggregate check. Branch-rule activation remains a separate
administrative operation after a successful workflow run. The initial synthetic
rule cases cannot substantiate AI prompt quality or production precision.

See [the specification](../AGENT_EVALS.md) for scope and activation limits.
