# Python 3.11 CI Guardrail

This folder documents and anchors caRINA's minimum Python runtime requirement.

## Purpose

caRINA's runtime code uses Python 3.11+ features such as `datetime.UTC`. The repository's CI must therefore stay on Python 3.11 or newer.

## Enforcement

The executable regression guard lives at `tests/test_python_runtime.py`. That test fails immediately when the suite runs on Python < 3.11, producing a targeted compatibility error instead of allowing later import failures.

## Maintainer rule

When changing GitHub Actions, local tooling, or packaging metadata:

1. Keep the supported minimum at Python 3.11 or newer.
2. Keep CI, tests, and package metadata aligned.
3. Do not weaken or bypass the guard to make CI green.
4. If the minimum runtime changes, update this folder and the regression test in the same PR.

## Related work

- PR #8 aligned Verify, Lint/unit-test, and Security workflows to Python 3.11.
- PR #9 adds the persistent regression guard.
