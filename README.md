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

## Archive Planning

Preview archive moves without changing anything:

```sh
make archive-dry-run
```

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
