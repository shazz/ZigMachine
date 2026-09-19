"""Renders a parsed Tutorial into docs/TUTORIAL.html."""
from __future__ import annotations

import html as _html
import re

from . import ROOT, esc, render_markdown
from .highlight import highlight
from .tutorial_parse import LANGS, Section, Tutorial, parse
from .tutorial_theme import LANG_NAMES, PREPAINT, TEMPLATE, comparepick, langpick

# The md's bold lead-ins are a real convention (every step uses them); each gets
# its own treatment on the page, so the reader can see at a glance which
# paragraph is the goal, which is the checkpoint and which is the warning.
LEAD_CLASSES = {
    "goal": "goal",
    "concept": "concept",
    "zig vs c/rust": "vs",
    "what you should see": "see",
    "what you should hear": "see",
    "common mistakes": "mistakes",
    "the line numbers": "concept",
}
LEAD_RE = re.compile(r"<p><strong>([^<]+?)\.</strong>")
CODE_RE = re.compile(r'<pre><code(?: class="language-([\w+#-]+)")?>([\s\S]*?)</code></pre>')
STAMP_RE = re.compile(r'(\.(?:js|css))\?v=[0-9a-f]+')

# The cart each language's finished tutorial screen builds to (docs/).
CARTS = {"zig": "demo-tutorial", "c": "demo-c-tutorial", "rust": "demo-rust-tutorial"}


def label_leads(markup: str) -> str:
    """Tag each `**Label.**` paragraph with a class so CSS can style the eyebrow."""

    def repl(m: re.Match[str]) -> str:
        kind = LEAD_CLASSES.get(m.group(1).strip().lower(), "note")
        return f'<p class="lead lead-{kind}"><strong>{m.group(1)}.</strong>'

    return LEAD_RE.sub(repl, markup)


def code_blocks(markup: str, default_lang: str = "") -> str:
    """Re-render markdown's <pre><code> into a captioned, highlighted block."""

    def repl(m: re.Match[str]) -> str:
        lang = (m.group(1) or default_lang or "").lower()
        code = _html.unescape(m.group(2)).rstrip("\n")
        n = len(code.splitlines())
        tag = f'<span class="cb-lang">{esc(lang)}</span>' if lang else ""
        return (
            f'<figure class="cb"{f" data-lang={lang}" if lang else ""}>'
            f'<figcaption>{tag}<span class="cb-n">{n} line{"" if n == 1 else "s"}</span>'
            f'<button class="cb-copy" type="button">Copy</button></figcaption>'
            f"<pre><code>{highlight(code, lang)}</code></pre></figure>"
        )

    return CODE_RE.sub(repl, markup)


def _prose(md: str, lang: str = "") -> str:
    return code_blocks(label_leads(render_markdown(md)), lang) if md.strip() else ""


def render_langs(sec: Section) -> str:
    if not sec.langs:
        return ""
    names = dict((v, k) for k, v in LANGS.items())
    blocks = "".join(
        f'<section class="lang" data-lang="{b.lang}" id="{sec.slug}-{b.lang}">'
        f"<h3>{names[b.lang]}</h3>{_prose(b.md, b.lang)}</section>"
        for b in sec.langs
    )
    return f'<div class="langs">{blocks}</div>'


def render_section(sec: Section) -> str:
    runnable = bool(sec.langs)
    run = (
        f'<button class="run" data-step="{sec.number}" type="button">'
        f"&#9654; Run</button>" if runnable else ""
    )
    num = f'<span class="num">{sec.number:02d}</span>' if sec.is_step else ""
    kind = "step" if sec.is_step else "plain"
    attr = f' data-step="{sec.number}"' if sec.is_step else ""
    return (
        f'<section class="{kind}" id="{sec.slug}"{attr}>'
        f'<header class="step-h">{num}<h2>{esc(sec.title)}</h2>{run}</header>'
        f'<div class="shared">{_prose(sec.before)}</div>'
        f"{render_langs(sec)}"
        f'<div class="shared after">{_prose(sec.after)}</div>'
        f'<div class="run-slot"></div></section>'
    )


def rail(t: Tutorial) -> str:
    out = []
    for sec in t.sections:
        n = f'<span class="rn">{sec.number:02d}</span>' if sec.is_step else '<span class="rn">·</span>'
        out.append(f'<a href="#{sec.slug}" data-slug="{sec.slug}">{n}{esc(sec.title)}</a>')
    return "\n".join(out)


def cards() -> str:
    """The first-visit chooser. Line counts come from the real scene sources."""
    src = {"zig": "apps/zig/scenes/tutorial.zig", "c": "apps/c/scenes/tutorial.c",
           "rust": "apps/rust/scenes/tutorial.rs"}
    via = {"zig": "through the ZigOS library", "c": "straight at the sealed ABI",
           "rust": "straight at the sealed ABI, no_std"}
    out = []
    for key, name in LANG_NAMES:
        path = ROOT / src[key]
        n = len(path.read_text().splitlines()) if path.is_file() else 0
        out.append(
            f'<button class="card" data-lang="{key}" type="button"><b>{name}</b>'
            f'<span class="card-n">{n} lines</span>'
            f'<span class="card-v">{via[key]}</span></button>'
        )
    return "".join(out)


def build() -> str:
    t = parse((ROOT / "docs" / "TUTORIAL.md").read_text())
    return TEMPLATE.format(
        prepaint=PREPAINT,
        title=esc(t.title),
        intro=_prose(t.intro),
        nsteps=len(t.steps),
        langpick=langpick(),
        comparepick=comparepick(),
        rail=rail(t),
        cards=cards(),
        sections="\n".join(render_section(s) for s in t.sections),
    )


def unstamped(text: str) -> str:
    """The page minus cache_bust.py's ?v= hashes, which it rewrites after generation."""
    return STAMP_RE.sub(r"\1", text)
