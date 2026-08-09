#!/usr/bin/env sh
set -eu

base_ref="${1:-HEAD~1}"
changed="$(git diff --name-only "$base_ref"...HEAD)"
pipeline_changed="$(printf '%s\n' "$changed" | grep -E '^(src/file_workflow\.py|tests/test_file_workflow\.py)$' || true)"
spec_changed="$(printf '%s\n' "$changed" | grep -E '^docs/(FILE_PIPELINE_SPEC|SECURITY_REQUIREMENTS)\.md$' || true)"

if [ -n "$pipeline_changed" ] && [ -z "$spec_changed" ]; then
  echo "Pipeline changes require FILE_PIPELINE_SPEC.md or SECURITY_REQUIREMENTS.md updates." >&2
  exit 1
fi
