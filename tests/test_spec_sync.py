"""Exercise the real specification gate against isolated Git histories."""
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/verify-spec-sync.sh"
ZERO = "0" * 40


class SpecSyncTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "-q")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "user.name", "Test")
        self.commit({"README.md": "initial"})
        self.base = self.git("rev-parse", "HEAD").stdout.strip()

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.root, text=True,
                              capture_output=True, check=True)

    def commit(self, files):
        for name, contents in files.items():
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(contents)
        self.git("add", ".")
        self.git("commit", "-qm", "fixture")

    def gate(self, base):
        return subprocess.run(["sh", str(SCRIPT), base], cwd=self.root,
                              text=True, capture_output=True)

    def test_new_branch_without_pipeline_passes(self):
        self.assertEqual(self.gate(ZERO).returncode, 0)

    def test_new_branch_pipeline_without_spec_fails(self):
        self.commit({"src/file_workflow.py": "# pipeline"})
        result = self.gate(ZERO)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Pipeline changes require", result.stderr)

    def test_new_branch_pipeline_with_spec_passes(self):
        self.commit({"src/file_workflow.py": "# pipeline",
                     "docs/FILE_PIPELINE_SPEC.md": "# Specification"})
        self.assertEqual(self.gate(ZERO).returncode, 0)

    def test_normal_change_without_spec_fails(self):
        self.commit({"tests/test_file_workflow.py": "# test"})
        self.assertNotEqual(self.gate(self.base).returncode, 0)

    def test_normal_change_with_security_doc_passes(self):
        self.commit({"src/file_workflow.py": "# pipeline",
                     "docs/SECURITY_REQUIREMENTS.md": "# Security"})
        self.assertEqual(self.gate(self.base).returncode, 0)

    def test_invalid_nonzero_base_fails_closed(self):
        self.assertNotEqual(self.gate("1" * 40).returncode, 0)
