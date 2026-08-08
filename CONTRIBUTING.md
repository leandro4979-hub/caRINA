# Contributing to the CARINA Codex

## File naming

- Lowercase, hyphen-separated: `async-await.md`, not `Async Await.md`.
- One topic per file. Split when a file exceeds approximately 200 lines.
- Place language-specific snippets under `snippets/<language>/`.

## Entry format

Every entry follows this shape:

````markdown
### Entry title

One sentence describing what it does and when to use it.

```language
Runnable code
```

**Notes:** Optional non-obvious caveats.
````

## Required front matter

Each file opens with:

````markdown
# Title

> One-line summary.
> Last verified: YYYY-MM-DD
````

## Rules

1. Code must run as written — no placeholders, pseudocode, or `TODO` comments.
2. Define a term once in [glossary.md](glossary.md) and link to it elsewhere.
3. Do not explain self-evident code. Comment non-obvious logic only.
4. Update `Last verified` whenever you touch an entry.
5. All internal links must resolve; CI fails otherwise.

## Commit messages

```text
<section>: <imperative summary>

snippets: add Swift URLSession retry helper
tools: correct git rebase --onto argument order
```
