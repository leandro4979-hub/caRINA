from pathlib import Path
import tempfile
import unittest

from src.build_dashboard import (
    Listener,
    classify_codex_folder,
    parse_bullets,
    parse_markdown_tables,
    status_for_port,
)


class BuildDashboardTests(unittest.TestCase):
    def test_parse_markdown_tables_skips_separator_rows(self) -> None:
        markdown = """
| Name | Status |
| --- | --- |
| Codex | Active |
"""

        self.assertEqual(parse_markdown_tables(markdown), [[["Name", "Status"], ["Codex", "Active"]]])

    def test_parse_bullets_returns_plain_items(self) -> None:
        markdown = """
# Inbox

- First item
- Second item
"""

        self.assertEqual(parse_bullets(markdown), ["First item", "Second item"])

    def test_status_for_port_reports_online_only_when_listener_matches(self) -> None:
        listeners = [Listener(command="node", pid="123", port="18789", address="*:18789 (LISTEN)")]

        self.assertEqual(status_for_port("18789", listeners), "online")
        self.assertEqual(status_for_port("11434", listeners), "check")

    def test_classify_codex_folder_keeps_repository_markers(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "package.json").write_text("{}", encoding="utf-8")

            status, reason = classify_codex_folder(path, size_bytes=2, files=1)

        self.assertEqual(status, "keep")
        self.assertIn("repository", reason)

    def test_classify_codex_folder_flags_empty_folder_as_delete_candidate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            status, reason = classify_codex_folder(Path(directory), size_bytes=0, files=0)

        self.assertEqual(status, "delete candidate")
        self.assertIn("No files", reason)


if __name__ == "__main__":
    unittest.main()
