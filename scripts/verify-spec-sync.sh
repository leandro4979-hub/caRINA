#!/usr/bin/env sh
set -eu

base_ref="${1:-HEAD~1}"
case "$base_ref" in
  0000000000000000000000000000000000000000)
    # A branch-creation push has no previous commit. Inspect its full tree.
    empty_tree="$(git hash-object -t tree --stdin </dev/null)"
    changed="$(git diff --name-only "$empty_tree" HEAD)"
    ;;
  *)
    # Invalid or unavailable nonzero bases must continue to fail closed.
    changed="$(git diff --name-only "$base_ref"...HEAD)"
    ;;
esac
pipeline_changed="$(printf '%s\n' "$changed" | grep -E '^(src/file_workflow\.py|tests/test_file_workflow\.py)$' || true)"
spec_changed="$(printf '%s\n' "$changed" | grep -E '^docs/(FILE_PIPELINE_SPEC|SECURITY_REQUIREMENTS)\.md$' || true)"

if [ -n "$pipeline_changed" ] && [ -z "$spec_changed" ]; then
  echo "Pipeline changes require FILE_PIPELINE_SPEC.md or SECURITY_REQUIREMENTS.md updates." >&2
  exit 1
fi
