import unittest
import io
from contextlib import redirect_stdout

from carina_type import Request, Router, RouterError, choose_mode, main, resolve_text


class Clipboard:
    def __init__(self, value="original"):
        self.value = value
        self.history = []
    def copy(self, value):
        self.value = value
        self.history.append(value)
    def paste(self):
        return self.value


class Input:
    def __init__(self):
        self.writes = []
        self.hotkeys = []
        self.keys = []
    def write(self, value, interval=0.03): self.writes.append(value)
    def hotkey(self, *keys): self.hotkeys.append(keys)
    def press(self, key): self.keys.append(key)


class AI:
    def generate(self, action, text, context, preset): return f"generated: {text}"


class RouterTests(unittest.TestCase):
    def setUp(self):
        self.clipboard = Clipboard()
        self.input = Input()
        self.config = {"templates": {"sig": "Best,\nCarina"}, "forms": {"contact": ["Ada", "ada@example.com"]}, "clipboard_restore": True}

    def router(self, approved=True):
        return Router(self.clipboard, self.input, self.config, AI(), lambda *_: approved)

    def test_auto_mode_prefers_typing_for_short_single_line_text(self):
        self.assertEqual("type", choose_mode(Request(action="type"), "hello"))
        self.assertEqual("paste", choose_mode(Request(action="paste"), "hello"))
        self.assertEqual("paste", choose_mode(Request(action="reply"), "a\nb"))

    def test_cancel_never_touches_input_or_clipboard(self):
        result = self.router(False).run(Request(action="paste", text="hello"))
        self.assertEqual("cancelled", result["status"])
        self.assertEqual([], self.clipboard.history)
        self.assertEqual([], self.input.hotkeys)

    def test_preview_never_touches_input_or_clipboard(self):
        result = self.router().run(Request(action="paste", text="hello", preview_only=True))
        self.assertEqual("preview", result["status"])
        self.assertEqual([], self.clipboard.history)
        self.assertEqual([], self.input.hotkeys)

    def test_paste_restores_clipboard(self):
        self.router().run(Request(action="paste", text="hello", mode="paste"))
        self.assertEqual("original", self.clipboard.value)
        self.assertEqual(["hello", "original"], self.clipboard.history)
        self.assertEqual([("command", "v")], self.input.hotkeys)

    def test_template_and_ai_resolution(self):
        self.assertEqual("Best,\nCarina", resolve_text(Request(action="paste", template="sig"), self.config, None))
        self.assertEqual("generated: draft", resolve_text(Request(action="reply", text="draft"), self.config, AI()))

    def test_fill_form_tabs_between_fields(self):
        result = self.router().run(Request(action="fill_form", template="contact"))
        self.assertEqual("confirmed", result["status"])
        self.assertEqual(["tab"], self.input.keys)

    def test_invalid_request_is_rejected(self):
        with self.assertRaises(RouterError):
            Request.from_mapping({"action": "delete"})

    def test_json_preview_runs_without_gui_dependencies(self):
        import sys
        old_stdin = sys.stdin
        try:
            sys.stdin = io.StringIO('{"action":"paste","text":"hello","preview_only":true}')
            output = io.StringIO()
            with redirect_stdout(output):
                self.assertEqual(0, main(["--json"]))
            self.assertIn('"status": "preview"', output.getvalue())
        finally:
            sys.stdin = old_stdin


if __name__ == "__main__":
    unittest.main()
