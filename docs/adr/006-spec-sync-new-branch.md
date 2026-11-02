# ADR-006: Specification checks on new branches

A new-branch push has no previous commit and supplies an all-zero SHA.
For CI-SYNC-001, compare the full committed tree against Git's empty tree.
This conservatively retains documentation checks on the first push.
Do not silently skip the gate or replace invalid nonzero references.
Ordinary pushes and pull requests retain the merge-base comparison.

Tests cover root commits, pipeline-only additions, accompanying documentation,
normal comparisons and invalid nonzero bases. No runtime authority changes.
