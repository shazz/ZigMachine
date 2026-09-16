"""The generation-time highlighter must never corrupt the code it styles."""
from __future__ import annotations

import html
import re
import unittest

from docgen.highlight import highlight

TAGS = re.compile(r"<[^>]+>")


def plain(markup: str) -> str:
    """The rendered block back to source text, so we can prove nothing was lost."""
    return html.unescape(TAGS.sub("", markup))


class Highlight(unittest.TestCase):
    def test_zig_keywords_comments_and_numbers(self) -> None:
        out = highlight("const W: u16 = 320; // wide", "zig")
        self.assertIn('<span class="tok-kw">const</span>', out)
        self.assertIn('<span class="tok-num">320</span>', out)
        self.assertIn('<span class="tok-cm">// wide</span>', out)

    def test_c_preprocessor_and_rust_attributes(self) -> None:
        self.assertIn('class="tok-pp"', highlight("#define FLOOR_Y 160", "c"))
        self.assertIn('class="tok-at"', highlight("#[no_mangle]\nfn f() {}", "rust"))

    def test_a_call_is_a_function_a_keyword_is_not(self) -> None:
        out = highlight("if (draw(1)) {}", "c")
        self.assertIn('<span class="tok-kw">if</span>', out)
        self.assertIn('<span class="tok-fn">draw</span>', out)

    def test_html_is_escaped_everywhere(self) -> None:
        out = highlight('x < 1 && s = "a&b>c";', "c")
        self.assertNotIn("<1", out)
        self.assertIn("&amp;&amp;", out)
        self.assertIn("&lt;", out)

    def test_unknown_language_passes_through_escaped(self) -> None:
        self.assertEqual(highlight("a < b", "brainfuck"), "a &lt; b")

    def test_round_trip_preserves_the_source_exactly(self) -> None:
        for lang in ("zig", "c", "rust", "bash"):
            src = 'fn main() { /* c */ let s = "x<y&z"; return 0x1F; } // end'
            self.assertEqual(plain(highlight(src, lang)), src, lang)


if __name__ == "__main__":
    unittest.main()
