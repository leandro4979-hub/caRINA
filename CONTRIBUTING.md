# Contributing to caRINA

## Development flow

1. Create a short-lived branch from `main`.
2. Make the smallest source or documentation edit that solves the task.
3. Run `make verify` from the repository root.
4. Review `git status --short` and commit only intentional changes.

## Codex entries

- Use lowercase, hyphen-separated filenames.
- Keep one topic per file; split files exceeding approximately 200 lines.
- Put language-specific snippets in `snippets/<language>/`.
- Every code sample must run as written, with imports and invocation included.
- Define recurring terms in [glossary.md](glossary.md) and use relative links.
- Update `Last verified` whenever you touch an entry.

## Safety

- Do not commit credentials, tokens, passwords, or generated dashboard output.
- Do not delete generated or archived material without explicit approval.
- Do not start or stop services only to make verification pass.
