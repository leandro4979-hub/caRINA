"""Exercise the workflow's actual aggregate shell script, without PyYAML."""
import itertools
import os
from pathlib import Path
import subprocess
import textwrap
import unittest


class AggregateGateTests(unittest.TestCase):
    def test_all_dependency_results(self):
        workflow = Path(__file__).resolve().parents[3] / '.github/workflows/agent-evals.yml'
        text = workflow.read_text()
        aggregate = text.split('  agent-evals:\n', 1)[1]
        self.assertIn('    if: always()\n', aggregate)
        script = textwrap.dedent(aggregate.split('        run: |\n', 1)[1])
        states = ['success', 'failure', 'cancelled', 'skipped']
        for detected, required, evaluated, approval in itertools.product(
                states, ['true', 'false', ''], states, states):
            with self.subTest(detected=detected, required=required,
                              evaluated=evaluated, approval=approval):
                expected = detected == 'success' and (
                    required == 'true' and evaluated == approval == 'success'
                    or required == 'false' and evaluated == approval == 'skipped')
                result = subprocess.run(
                    ['bash', '-c', script], capture_output=True, timeout=5,
                    env={**os.environ, 'DETECT_RESULT': detected,
                         'REQUIRED': required, 'EVAL_RESULT': evaluated,
                         'APPROVAL_RESULT': approval})
                self.assertEqual(result.returncode == 0, expected)


if __name__ == '__main__':
    unittest.main()
