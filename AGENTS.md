# AGENTS.md

## Purpose

This repository builds and operates CARINA: an iOS client, authenticated macOS bridge, and local operational tooling.

Use this file as the default execution guide for coding agents. Keep changes minimal, verifiable, and scoped.

## First Commands

Run from repository root:

```sh
make verify
```

Before iOS device builds:

```sh
make ios-device-build
```

Useful operational targets:

```sh
make dashboard
make forge
make forge-status
make deployment-guardian-status
```

## Repository Boundaries

- `apps/bridge/`: authenticated HTTP/WebSocket bridge, routing, and permission-gated execution.
- `apps/ios/`: SwiftUI iOS client (`Carina.xcodeproj`) and tests.
- `scripts/`: launch agent installers and operational services (dashboard, forge, guardian, device control).
- `src/`: dashboard/token/archive utilities used by `make verify`.
- `tests/`: Python unit tests for bridge/dashboard/forge/deployment logic.
- `docs/`: deployment and operational guidance.

## Source of Truth

Prefer linking to canonical docs instead of re-encoding rules:

- Project overview and runbook: [README.md](README.md)
- Contribution and verification policy: [CONTRIBUTING.md](CONTRIBUTING.md)
- iPhone deployment and troubleshooting: [docs/ios-device-deployment.md](docs/ios-device-deployment.md)
- Current operational handoff state: [HANDOFF.md](HANDOFF.md)

## Non-Negotiable Conventions

- Always run `make verify` before committing.
- Fix the first meaningful failing verification step, then re-run `make verify`.
- Do not commit generated output (for example `dist/dashboard.html`).
- Keep commits focused; avoid unrelated edits in the same commit.
- Never commit tokens, API keys, passwords, or credentials.
- Do not start/stop/reinstall services unless the task requires it.

## iOS + Bridge Pitfalls

- iPhone bridge host must not be `127.0.0.1`, `localhost`, or `::1`.
- For signed device builds, use the configured Xcode beta path in `Makefile` (`XCODE_DEVELOPER_DIR`).
- For physical device reliability, prefer `make ios-device-build` over ad hoc xcodebuild invocations.
- Treat execute-level actions as approval-gated flows; do not bypass permission checks in bridge or iOS layers.

## Editing Guidance

- Preserve existing architecture and naming style in each area (bridge Python, iOS SwiftUI, scripts).
- Make the smallest viable change to satisfy the request.
- If behavior changes, add or update tests in `tests/` (and iOS tests when applicable).
- When adding operational commands, wire them through `Makefile` when practical.
