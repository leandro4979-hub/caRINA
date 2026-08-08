# Git basics

## Start a repository

```sh
git init
git add .
git commit -m "Initial commit"
```

Creates a local repository and saves its first snapshot.

## Work on a change

```sh
git switch -c feature/short-description
git status
git add path/to/file
git commit -m "Describe the change"
```

Creates an isolated branch and commits a focused change.

## Sync with a remote

```sh
git remote add origin https://github.com/OWNER/REPOSITORY.git
git push -u origin main
```

Associates the local repository with GitHub and publishes the main branch.

## Inspect history

```sh
git log --oneline --decorate --graph
git diff
```

Shows a compact history graph and uncommitted changes.

## Update your branch

```sh
git fetch origin
git rebase origin/main
```

Replays your local commits on top of the current remote main branch.

## Undo an unstaged change

```sh
git restore path/to/file
```

Restores a tracked file to the version from the latest commit.
