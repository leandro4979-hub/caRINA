# Contributing to caRINA

caRINA is Leandro's local AgentOps dashboard project. Keep changes small,
verify them locally, and treat the AgentOps Markdown files as the source of
truth for dashboard content.

## Development Flow

1. Create a short-lived branch from `main` for each change.
2. Make the smallest source or documentation edit that solves the task.
3. Run the verification gate from the repo root:

   ```sh
   make verify
   ```

4. Review `git status --short` before committing.
5. Commit only intentional source, test, and documentation changes.
6. Push the branch and confirm GitHub Actions `Verify` passes.

For tiny local-only updates, committing directly to `main` is acceptable after
`make verify` passes.

## Verification Gate

`make verify` is the required local check before every commit. It currently:

- compiles the Python scripts;
- runs the unit tests;
- regenerates `dist/dashboard.html`;
- runs a token-counter smoke check.

If verification fails, fix the first meaningful failure and run it again. Do
not start, stop, or reinstall services to make tests pass unless the task
explicitly requires that action.

## Generated Files

`dist/dashboard.html` is generated output and is ignored by git. Running
`make dashboard` or `make verify` may rewrite it from:

- AgentOps Markdown notes in `/Users/leandrofajardo/Documents/AgentOps`;
- live local listener data collected by the dashboard builder.

Commit the source or note changes that caused the dashboard update, not the
generated dashboard file.

## AgentOps and Dashboard Updates

Update AgentOps when durable operating state changes, such as:

- a project status or next action changes;
- a service owner, port, launch method, or safety rule changes;
- a skill, agent pattern, token policy, or dashboard input changes.

Regenerate the dashboard after AgentOps or dashboard source data changes:

```sh
make dashboard
```

The full `make verify` command also regenerates the dashboard.

## Commit Expectations

Use concise, action-oriented commit messages, for example:

```text
Add caRINA verification tests
Document verification gate
```

Keep commits focused. Avoid bundling unrelated AgentOps notes, dashboard code,
and cleanup work into one commit unless they are part of the same task.

## Safety Rules

- Do not commit token, API key, password, or credential values.
- Do not delete generated or archived material without explicit approval.
- Do not duplicate long-lived services; MagnoliaOS Core is managed by the
  `com.leandro.magnoliaos.core` LaunchAgent.
- Prefer inspection and dry runs before any action that changes local runtime
  state.
