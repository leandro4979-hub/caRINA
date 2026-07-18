---
description: "Implement a CARINA repo task with minimal risk and verification"
name: "CARINA: Implement Verified Change"
argument-hint: "Describe the code change you want (scope, constraints, acceptance criteria)"
agent: "agent"
---
Implement the requested change in this repository using the smallest safe diff.

Task request:
- Use the user-provided request as the source of truth.
- If the request is ambiguous, ask only the minimum clarifying question needed.

Execution requirements:
1. Inspect relevant files before editing.
2. Keep behavior unchanged outside requested scope.
3. Prefer existing project patterns and naming.
4. Add or update tests when behavior changes.
5. Run verification and report concrete results.

Repository defaults:
- Run `make verify` before finalizing.
- If iOS device build behavior changed, also run `make ios-device-build` when feasible.
- Never expose or commit secrets.
- Do not commit generated outputs such as `dist/dashboard.html`.

Final response format:
1. What changed (files + behavior)
2. Validation run (commands + pass/fail)
3. Risks, assumptions, or follow-up actions

Use these repo references when needed:
- [AGENTS.md](../../AGENTS.md)
- [CONTRIBUTING.md](../../CONTRIBUTING.md)
- [README.md](../../README.md)
