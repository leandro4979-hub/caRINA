# caRINA

caRINA is Leandro's local AgentOps dashboard project and engineering codex.

## Dashboard

Build and verify the local dashboard:

```sh
make verify
```

The dashboard reads AgentOps Markdown notes and writes `dist/dashboard.html`.

## Codex

| Section | Purpose |
| --- | --- |
| [Glossary](glossary.md) | Definitions of key terms |
| [Snippets](snippets/README.md) | Reusable, runnable code by language |
| [Patterns](patterns/README.md) | Architectural patterns and tradeoffs |
| [Shortcuts](shortcuts/README.md) | Keyboard, terminal, and IDE productivity |
| [Tools](tools/git-basics.md) | Development tooling references |

## Development

Run `make verify` before committing. Commit source and documentation changes, not generated dashboard output. See [CONTRIBUTING.md](CONTRIBUTING.md) for project and codex conventions.
