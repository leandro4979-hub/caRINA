import unittest

from src.token_counter import estimate_tokens_from_text, read_json_payload


class TokenCounterTests(unittest.TestCase):
    def test_estimate_tokens_from_text_never_returns_zero(self) -> None:
        self.assertEqual(estimate_tokens_from_text(""), 1)

    def test_estimate_tokens_from_text_uses_conservative_character_ratio(self) -> None:
        self.assertEqual(estimate_tokens_from_text("abcdefgh"), 2)

    def test_read_json_payload_returns_none_without_input(self) -> None:
        self.assertIsNone(read_json_payload(None, None))

    def test_read_json_payload_parses_inline_json(self) -> None:
        self.assertEqual(read_json_payload('[{"role":"user","content":"hi"}]', None), [{"role": "user", "content": "hi"}])


if __name__ == "__main__":
    unittest.main()
