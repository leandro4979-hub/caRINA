from pathlib import Path
import tempfile
import unittest

from src.build_dashboard import (
    Listener,
    classify_codex_folder,
    css_class,
    folder_counts,
    folder_stats,
    human_size,
    inline,
    parse_bullets,
    parse_markdown_tables,
    render_table,
    status_for_port,
)


class ParseMarkdownTablesTests(unittest.TestCase):
    def test_skips_separator_rows(self) -> None:
        markdown = """
| Name | Status |
| --- | --- |
| Codex | Active |
"""
        self.assertEqual(parse_markdown_tables(markdown), [[["Name", "Status"], ["Codex", "Active"]]])

    def test_returns_multiple_tables(self) -> None:
        markdown = """
| A | B |
| - | - |
| 1 | 2 |

| C | D |
| - | - |
| 3 | 4 |
"""
        tables = parse_markdown_tables(markdown)
        self.assertEqual(len(tables), 2)
        self.assertEqual(tables[0], [["A", "B"], ["1", "2"]])
        self.assertEqual(tables[1], [["C", "D"], ["3", "4"]])

    def test_returns_empty_list_for_no_tables(self) -> None:
        self.assertEqual(parse_markdown_tables("# Heading\n\nJust prose."), [])


class ParseBulletsTests(unittest.TestCase):
    def test_returns_plain_items(self) -> None:
        markdown = """
# Inbox

- First item
- Second item
"""
        self.assertEqual(parse_bullets(markdown), ["First item", "Second item"])

    def test_returns_empty_list_when_no_bullets(self) -> None:
        self.assertEqual(parse_bullets("No bullets here."), [])


class StatusForPortTests(unittest.TestCase):
    def test_reports_online_only_when_listener_matches(self) -> None:
        listeners = [Listener(command="node", pid="123", port="18789", address="*:18789 (LISTEN)")]
        self.assertEqual(status_for_port("18789", listeners), "online")
        self.assertEqual(status_for_port("11434", listeners), "check")

    def test_reports_check_when_listener_list_is_empty(self) -> None:
        self.assertEqual(status_for_port("5000", []), "check")


class ClassifyCodexFolderTests(unittest.TestCase):
    def test_keeps_repository_markers(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "package.json").write_text("{}", encoding="utf-8")
            status, reason = classify_codex_folder(path, size_bytes=2, files=1)
        self.assertEqual(status, "keep")
        self.assertIn("repository", reason)

    def test_flags_empty_folder_as_delete_candidate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            status, reason = classify_codex_folder(Path(directory), size_bytes=0, files=0)
        self.assertEqual(status, "delete candidate")
        self.assertIn("No files", reason)

    def test_archives_small_folder_without_special_markers(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "notes.txt").write_text("hello", encoding="utf-8")
            status, _ = classify_codex_folder(path, size_bytes=5, files=1)
        self.assertEqual(status, "archive")

    def test_flags_large_unmarked_folder_for_review(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "data.bin").write_text("x" * 10, encoding="utf-8")
            status, _ = classify_codex_folder(path, size_bytes=1_000_000, files=1)
        self.assertEqual(status, "review")


class HumanSizeTests(unittest.TestCase):
    def test_formats_bytes(self) -> None:
        self.assertEqual(human_size(512), "512 B")

    def test_formats_kilobytes(self) -> None:
        self.assertEqual(human_size(2048), "2.0 KB")

    def test_formats_megabytes(self) -> None:
        self.assertEqual(human_size(2 * 1024 * 1024), "2.0 MB")

    def test_formats_gigabytes(self) -> None:
        self.assertEqual(human_size(3 * 1024 * 1024 * 1024), "3.0 GB")


class FolderStatsTests(unittest.TestCase):
    def test_counts_files_and_sizes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "a.txt").write_bytes(b"hello")
            (path / "b.txt").write_bytes(b"world!")
            size, files = folder_stats(path)
        self.assertEqual(files, 2)
        self.assertEqual(size, 11)

    def test_returns_zero_for_empty_directory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            size, files = folder_stats(Path(directory))
        self.assertEqual(size, 0)
        self.assertEqual(files, 0)


class FolderCountsTests(unittest.TestCase):
    def test_counts_each_status(self) -> None:
        from src.build_dashboard import CodexFolder
        folders = [
            CodexFolder(name="a", path=Path("/a"), date="2026-01-01", size_bytes=0, files=0, status="keep", reason=""),
            CodexFolder(name="b", path=Path("/b"), date="2026-01-01", size_bytes=0, files=0, status="archive", reason=""),
            CodexFolder(name="c", path=Path("/c"), date="2026-01-01", size_bytes=0, files=0, status="archive", reason=""),
        ]
        counts = folder_counts(folders)
        self.assertEqual(counts["keep"], 1)
        self.assertEqual(counts["archive"], 2)


class CssClassTests(unittest.TestCase):
    def test_lowercases_and_replaces_spaces(self) -> None:
        self.assertEqual(css_class("delete candidate"), "delete-candidate")

    def test_keep_is_unchanged(self) -> None:
        self.assertEqual(css_class("keep"), "keep")


class InlineTests(unittest.TestCase):
    def test_escapes_html_special_chars(self) -> None:
        self.assertIn("&amp;", inline("a & b"))
        self.assertIn("&lt;", inline("<tag>"))

    def test_wraps_backtick_spans_in_code_tags(self) -> None:
        result = inline("`hello`")
        self.assertIn("<code>hello</code>", result)


class RenderTableTests(unittest.TestCase):
    def test_returns_empty_string_for_empty_input(self) -> None:
        self.assertEqual(render_table([]), "")

    def test_renders_header_and_body_rows(self) -> None:
        html = render_table([["Name", "Value"], ["foo", "bar"]])
        self.assertIn("<th>", html)
        self.assertIn("<td>", html)
        self.assertIn("foo", html)
        self.assertIn("bar", html)


if __name__ == "__main__":
    unittest.main()

