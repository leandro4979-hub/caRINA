import re
import unittest
from pathlib import Path


VIEWS_ROOT = Path(__file__).resolve().parents[1] / "apps" / "ios" / "Carina" / "Views"
UI_STRING = re.compile(r'(?:Text|TextField|SecureField|Label)\("([^"\n]*)"')
UNESCAPED_SWIFT_EXPRESSION = re.compile(r"(?<!\\)\([A-Za-z_][A-Za-z0-9_.]*\)")


class SwiftUICopyTests(unittest.TestCase):
    def test_dynamic_ui_copy_uses_swift_interpolation(self):
        failures = []
        for source_path in sorted(VIEWS_ROOT.glob("*.swift")):
            source = source_path.read_text(encoding="utf-8")
            for line_number, line in enumerate(source.splitlines(), start=1):
                for match in UI_STRING.finditer(line):
                    literal = match.group(1)
                    if UNESCAPED_SWIFT_EXPRESSION.search(literal):
                        failures.append(f"{source_path.name}:{line_number}: {literal}")

        self.assertEqual(
            failures,
            [],
            "Dynamic SwiftUI copy contains an unescaped expression; use \\(expression):\n"
            + "\n".join(failures),
        )


if __name__ == "__main__":
    unittest.main()
