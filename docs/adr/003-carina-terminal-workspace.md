# ADR 003: caRINA terminal workspace stays non-executing

## Status

Proposed for the 0.4.0 prototype branch.

## Context

caRINA needs a tactile IDE-like macOS surface with visible panels for terminal
conversation, problems, logs, tasks, skills, and security. The visual design can
look operational enough that users may reasonably interpret panel contents as
trusted execution state.

The existing architecture intentionally keeps local Ollama conversation
separate from privileged action execution and approval.

## Decision

The 0.4.0 workspace is a presentation and reasoning surface only.

- The terminal continues to use the existing loopback Ollama client.
- Workspace panels may display only state held by the local view model or
  explicitly documented prototype checkpoints.
- Problems must not invent compiler/test failures.
- Logs must not duplicate prompt or model-response content.
- Tasks are visible development checkpoints, not autonomous/background jobs.
- Skills modify reasoning instructions only.
- Security shows the current boundary and verification state without granting
  authority.
- Any future shell, compiler, CI, deployment, secrets, or action integration
  requires a separate typed trusted provider and must preserve approval,
  authorization, replay, idempotency, privacy, and audit controls.

## Consequences

The prototype can feel like an IDE without creating a hidden execution path.
Some panels remain deliberately sparse until trusted providers exist. This is
preferable to displaying synthetic telemetry that could be mistaken for real
system evidence.

The macOS build and interactive behavior must be observed before the branch is
considered merge-ready.
