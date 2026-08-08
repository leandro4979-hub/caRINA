# GitHub CLI

## Authenticate

```sh
gh auth login
```

Authenticates the GitHub CLI with a browser-based sign-in flow.

## Clone a repository

```sh
gh repo clone OWNER/REPOSITORY
```

Clones a GitHub repository into the current directory.

## Create a pull request

```sh
gh pr create --fill
```

Opens a pull request using the current branch and commit metadata.

## Check pull-request status

```sh
gh pr status
```

Lists pull requests relevant to the authenticated user and repository.

## View workflow runs

```sh
gh run list --limit 10
```

Shows the ten most recent GitHub Actions workflow runs.
