# caRINA 0.4.0 terminal workspace prototype

## Status

Prototype only. This document describes the tactile macOS workspace added on
`feature/carina-terminal-v0.4.0`. The branch still requires an observed macOS
build and launch before it is a merge candidate.

## Goal

Give caRINA a visible, touchable development cockpit inspired by an IDE terminal
without silently granting new authority. The workspace should make state feel
physical while keeping the existing local Ollama and approval boundaries intact.

## Workspace panels

- **Terminal** — streamed local conversation, skill commands, stop/send controls.
- **Problems** — verified diagnostics only; currently surfaces pending Mac build
  verification instead of fabricating compiler output.
- **Logs** — privacy-minimized lifecycle state only. It does not duplicate prompts
  or model responses.
- **Tasks** — explicit prototype verification checkpoints, not background jobs.
- **Skills** — tactile selectors for Coding Standards and Security Audit reasoning
  modes.
- **Security** — visible local/shell/secrets/actions/remote-listener boundaries and
  build-verification state.

Keyboard navigation uses Command-1 through Command-6 for the six panels.
Command-Return sends and Command-Period cancels generation.

## Trust boundary

This change is presentation plus local reasoning guidance. It does not add a
shell executor, remote listener, cloud fallback, secret reader, deployment
client, action executor, or approval bypass. Ollama remains loopback-only at
`127.0.0.1:11434` through the existing client.

The Problems, Logs, Tasks, and Security panels must not pretend that work ran.
Any future live compiler/test/task/deployment integration needs a typed trusted
provider that reports its own evidence and preserves the existing approval and
audit rules.

## Acceptance checks

Before merge, verify on macOS:

1. `cd CarinaMacApp && swift build` succeeds.
2. `swift run CarinaMacApp` opens the app without an unhandled failure.
3. Command-1 through Command-6 select the intended panels.
4. Panel buttons and terminal controls provide haptic feedback where supported.
5. `/audit`, `/standards`, `/skill off`, send, and stop still behave correctly.
6. Ollama streaming remains loopback-only.
7. Logs do not reproduce prompt or model-response content.
8. No shell, listener, remote fallback, secret access, or action executor is
   introduced.

## Known limitation

No macOS build or interactive run was available from the GitHub connector
session that authored this prototype. Compile and runtime behavior remain
**UNVERIFIED** until the acceptance checks above are observed.
