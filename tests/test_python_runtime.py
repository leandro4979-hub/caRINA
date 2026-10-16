import sys
import unittest


MINIMUM_PYTHON = (3, 11)
GUARDRAIL_DOC = "ci_guardrails/python311/README.md"


class PythonRuntimeCompatibilityTests(unittest.TestCase):
    def test_runtime_meets_repository_minimum(self) -> None:
        self.assertGreaterEqual(
            sys.version_info[:2],
            MINIMUM_PYTHON,
            (
                "caRINA requires Python 3.11+ because runtime code uses "
                "features such as datetime.UTC. Keep local tooling and CI "
                f"aligned with the repository minimum. See {GUARDRAIL_DOC}."
            ),
        )


if __name__ == "__main__":
    unittest.main()
