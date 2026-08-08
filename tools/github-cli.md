# GitHub CLI

> Verified `gh` commands for authentication, pull requests, and CI inspection.
> Last verified: 2026-08-07

## Setup

### Authenticate

```bash
gh auth login --hostname github.com --git-protocol https --web
gh auth status
```

Stores a token and configures Git to use it for HTTPS.

### Set the default repository

```bash
gh repo set-default leandro4979-hub/caRINA
```

Removes the need to pass `--repo` on every subsequent command.

## Pull requests

### Create a pull request

```bash
git push -u origin HEAD
gh pr create --fill --base main
```

Pushes the branch if needed, then opens the pull request.

### Watch checks

```bash
gh pr checks --watch
```

Blocks until every required check concludes.

### Merge once checks pass

```bash
gh pr merge --squash --delete-branch --auto
```

Queues a squash merge and deletes the branch afterward.

## Actions

### List recent workflow runs

```bash
gh run list --limit 10
```

Lists the ten most recent workflow runs.

### Show failing logs

```bash
gh run view --log-failed
```

Prints the failing log lines from the selected run.
