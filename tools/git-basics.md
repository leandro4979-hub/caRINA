# Git Basics

> Verified Git operations for daily use and recovery from common errors.
> Last verified: 2026-08-07

## Inspect

### Show what changed, staged and unstaged

```bash
git status --short --branch
```

Displays the working-tree state compactly.

### View commit history as a graph

```bash
git log --oneline --graph --decorate --all
```

Shows compact visual history across all branches.

## Modify

### Amend the last commit without changing its message

```bash
git add path/to/file
git commit --amend --no-edit
```

Adds a forgotten file to the latest local commit.

### Update your branch with the latest main, linearly

```bash
git fetch origin
git rebase origin/main
```

Replays local commits on the current remote main branch; do not rebase a branch others have pulled.

## Recover

### Undo the last commit, keeping the changes staged

```bash
git reset --soft HEAD~1
```

Moves `HEAD` back one commit while retaining the index contents.

### Recover a deleted branch or lost commit

```bash
git reflog
git switch -c recovered-branch <sha-from-reflog>
```

Lists prior `HEAD` positions and creates a branch at the selected commit.
