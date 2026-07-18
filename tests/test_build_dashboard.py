from pathlib import Path
import tempfile
import unittest

from src.build_dashboard import (
    Listener,
    ProjectSnapshot,
    build_html,
    classify_codex_folder,
    parse_bullets,
    parse_git_status_header,
    parse_lsof_listeners,
    planning_priorities,
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

    def test_lsof_parser_keeps_address_and_listener_marker_together(self) -> None:
        output = """COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
Python 42 user 7u IPv6 0x0 0t0 TCP *:51001 (LISTEN)
"""
        listeners = parse_lsof_listeners(output)
        self.assertEqual(len(listeners), 1)
        self.assertEqual(listeners[0].port, "51001")

    def test_git_status_parser_handles_new_and_tracking_branches(self) -> None:
        self.assertEqual(parse_git_status_header("## No commits yet on main"), ("main", 0, 0))
        self.assertEqual(
            parse_git_status_header("## feature...origin/feature [ahead 2, behind 1]"),
            ("feature", 2, 1),
        )

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

    def test_planning_priorities_are_derived_from_live_risks(self) -> None:
        project = ProjectSnapshot(
            name="CARINA",
            path="/tmp/CARINA",
            branch="main",
            dirty_files=2,
            commits_7d=4,
            ahead=0,
            behind=1,
            last_commit_at="2026-07-18T00:00:00Z",
            last_commit="abc test",
        )
        priorities = planning_priorities(
            [project],
            {"quarantined": 1},
            {"success": True, "profile_days_remaining": 5},
            5,
            6,
        )
        self.assertTrue(any("dirty" in item for item in priorities))
        self.assertTrue(any("behind" in item for item in priorities))
        self.assertTrue(any("quarantined" in item for item in priorities))

    def test_dashboard_contains_source_backed_operating_sections(self) -> None:
        html_text = build_html(
            {},
            [Listener("python", "1", "51001", "*:51001 (LISTEN)")],
            [],
            None,
            Path("/tmp/AgentOps"),
            [],
            "2026-07-18T00:00:00Z",
            {"ready": 3, "quarantined": 0, "operations": []},
            {"success": True, "profile_days_remaining": 5.0},
        )
        self.assertIn("Operating Pulse", html_text)
        self.assertIn("Project Performance", html_text)
        self.assertIn("Next Big Move", html_text)
        self.assertIn("Forge sources", html_text)


if __name__ == "__main__":
    unittest.main()
