import tempfile
import unittest
from pathlib import Path

from src.archive_codex_review import unique_destination


class UniqueDestinationTests(unittest.TestCase):
    def test_returns_original_path_when_destination_does_not_exist(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "new-folder"
            self.assertEqual(unique_destination(target), target)

    def test_appends_counter_when_destination_exists(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "folder"
            target.mkdir()
            result = unique_destination(target)
            self.assertEqual(result, target.with_name("folder-2"))

    def test_increments_counter_when_multiple_conflicts_exist(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "folder"
            target.mkdir()
            (target.with_name("folder-2")).mkdir()
            result = unique_destination(target)
            self.assertEqual(result, target.with_name("folder-3"))


if __name__ == "__main__":
    unittest.main()
