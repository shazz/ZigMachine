"""The captioned, highlighted code block both generated pages use.

Markdown gives us `<pre><code class="language-x">`; the page shows a figure with
the language, a line count and a Copy button (css/code.css, wired by each page's
script). Highlighting is done here at generation time (highlight.py).
"""
from __future__ import annotations

import html as _html
import re

from . import esc
from .highlight import highlight

CODE_RE = re.compile(r'<pre><code(?: class="language-([\w+#-]+)")?>([\s\S]*?)</code></pre>')


def code_figure(code: str, lang: str = "") -> str:
    """One highlighted block from raw source text."""
    code = code.rstrip("\n")
    n = len(code.splitlines())
    tag = f'<span class="cb-lang">{esc(lang)}</span>' if lang else ""
    return (
        f'<figure class="cb"{f" data-lang={lang}" if lang else ""}>'
        f'<figcaption>{tag}<span class="cb-n">{n} line{"" if n == 1 else "s"}</span>'
        f'<button class="cb-copy" type="button">Copy</button></figcaption>'
        f"<pre><code>{highlight(code, lang)}</code></pre></figure>"
    )


def code_blocks(markup: str, default_lang: str = "") -> str:
    """Re-render markdown's <pre><code> into captioned, highlighted blocks."""

    def repl(m: re.Match[str]) -> str:
        lang = (m.group(1) or default_lang or "").lower()
        return code_figure(_html.unescape(m.group(2)), lang)

    return CODE_RE.sub(repl, markup)
