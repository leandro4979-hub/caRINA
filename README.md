# caRINA

caRINA is the local build focus for Leandro's AgentOps setup.

The first working build is a local dashboard generator. It reads the Markdown
files in `/Users/leandrofajardo/Documents/AgentOps`, checks local listening
services, and writes a browser-ready dashboard to `dist/dashboard.html`.

## Run

```sh
make dashboard
```

Open the generated file:

```text
dist/dashboard.html
```

You can also run the script directly:

```sh
python3 src/build_dashboard.py
```

## Verify

```sh
make verify
```

## Production Verification Gate

caRINA is intentionally lightweight. The current build uses Python standard
library modules only; `tiktoken` is optional for more accurate token counts.
Use Python 3.9 or newer. This repo is currently verified locally with Python
3.9.6.

Before committing, run:

```sh
make verify
```

The verification gate checks:

- Python syntax for the dashboard builder, archive planner, and token counter.
- Unit tests for Markdown parsing, service status mapping, folder
  classification, and token-counter fallback behavior.
- Dashboard generation to `dist/dashboard.html`.
- Token-counter smoke behavior with direct text input.

`dist/dashboard.html` is generated output and is ignored by git. Running
`make verify` or `make dashboard` rewrites it from the current AgentOps
Markdown notes and live local listener data. Commit source and documentation
changes, not the generated dashboard file.

The token counter uses `tiktoken` when it is installed. If `tiktoken` is not
available, it falls back to a conservative character-based estimate so local
verification still works without extra dependencies.

Do not commit unless `make verify` passes. If verification fails:

- Read the first failing command in the output.
- Fix the smallest issue that explains that failure.
- Re-run `make verify`.
- Do not start or stop services just to make tests pass unless the failure is
  explicitly about live service state and the action has been approved.

## Archive Planning

Preview archive moves without changing anything:

```sh
make archive-dry-run
```

## Token Checks

Estimate prompt or AgentOps note size:

```sh
python3 src/token_counter.py --file /Users/leandrofajardo/Documents/AgentOps/skills.md
```

The helper uses `tiktoken` when installed. Without it, it returns a conservative
character-based estimate so the dashboard workflow still verifies cleanly.

## Current Build Target

- Keep Codex as the coordinator.
- Use caRINA as the first product surface.
- Read from AgentOps notes instead of duplicating state.
- Show live service health for Codex, OpenClaw, MagnoliaOS, and Ollama.
- Suggest keep/archive/delete-candidate labels for dated Codex session folders.
- Keep all cleanup actions manual until Leandro approves them.

## Current Dashboard Sections

- Live services
- Codex folder review
- Archive manifest summary
- Build priorities
- Inbox
- Agents
- Skills
- Token registry
- Service register
- Observed TCP listeners

## Support the Project

If this tool saved you some time, feel free to buy me a coffee!

[☕ Support via PayPal](https://www.paypal.com/ncp/payment/G4JVKQBYCCYUS)
