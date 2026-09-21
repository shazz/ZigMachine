"""Renders the guide's section bodies: API lists, constant tables, chapters."""
from __future__ import annotations

import re

from . import esc, render_markdown_file
from .codeblocks import code_blocks, code_figure
from .guide_content import EXAMPLES
from .zig_parse import Item

# `u16 x4 (ro) per-plane ...` — the register comments lead with a width and an
# optional element count / read-only flag; the table gives those their own column.
TYPE_RE = re.compile(r"^(u8|u16|u32|i32)(?:\s+x\s?(\d+))?\s*(\(ro\))?\s*(.*)$")
GROUP_RE = re.compile(r"^-{2,}\s*(.+?)\s*-{2,}$")  # `--- Palette management ---`
HEADING_RE = re.compile(r"<h([1-3])>([\s\S]*?)</h\1>")


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def split_sig(sig: str) -> tuple[str, str, str]:
    """`name(params) ret` -> (name, params, ret); params may nest parens."""
    start = sig.index("(")
    depth = 0
    for i in range(start, len(sig)):
        depth += {"(": 1, ")": -1}.get(sig[i], 0)
        if depth == 0:
            return sig[:start], sig[start:i + 1], sig[i + 1:].strip()
    return sig[:start], sig[start:], ""


def render_items(items: list[Item], prefix: str) -> str:
    out = []
    for it in items:
        if GROUP_RE.match(it.doc):  # a separator comment names the group that follows
            out.append(f'<h3 class="api-group">{esc(GROUP_RE.match(it.doc).group(1))}</h3>')
            it = Item(it.name, it.sig, "")
        name, params, ret = split_sig(it.sig)
        ident = f"{prefix}.{name}" if prefix else name
        doc = f'<p class="doc">{esc(it.doc)}</p>' if it.doc else ""
        out.append(
            f'<article class="api" id="{esc(ident)}"><code class="sig"><b class="fn">{esc(name)}</b>'
            f'{esc(params)} <span class="ret">{esc(ret)}</span></code>'
            f'<a class="anchor" href="#{esc(ident)}" aria-label="Link to {esc(name)}">#</a>{doc}</article>'
        )
    return "\n".join(out)


def _type_cell(doc: str) -> tuple[str, str]:
    m = TYPE_RE.match(doc)
    if not m:
        return "", doc
    width, count, ro, rest = m.groups()
    cell = width + (f" &times;{count}" if count else "") + ('<span class="ro">ro</span>' if ro else "")
    return f'<span class="type">{cell}</span>', rest


def render_consts(items: list[Item]) -> str:
    typed = any(TYPE_RE.match(it.doc) for it in items)
    head = "<th>Name</th><th>Value</th>" + ("<th>Type</th>" if typed else "") + "<th>Meaning</th>"
    rows = [f'<table class="regs"><thead><tr>{head}</tr></thead><tbody>']
    for it in items:
        ty, doc = _type_cell(it.doc) if typed else ("", it.doc)
        rows.append(
            f"<tr><td><code>{esc(it.name)}</code></td><td><code>{esc(it.sig)}</code></td>"
            + (f"<td>{ty}</td>" if typed else "")
            + f'<td class="meaning">{esc(doc)}</td></tr>'
        )
    rows.append("</tbody></table>")
    return "\n".join(rows)


def render_examples() -> str:
    return "\n".join(f"<h3>{esc(title)}</h3>{code_figure(code, 'zig')}" for title, code in EXAMPLES)


def render_chapter(rel: str, section_slug: str) -> str:
    """A repo markdown file as a chapter: its headings demoted two levels under
    the section title, given ids, and listed in a small table of contents."""
    markup = code_blocks(render_markdown_file(rel))
    toc: list[str] = []

    def demote(m: re.Match[str]) -> str:
        level = int(m.group(1)) + 2
        text = m.group(2)
        ident = f"{section_slug}-{slug(re.sub(r'<[^>]+>', '', text))}"
        if level <= 4:
            toc.append(f'<li class="toc-{level}"><a href="#{ident}">{text}</a></li>')
        return f'<h{level} id="{ident}">{text}</h{level}>'

    body = HEADING_RE.sub(demote, markup)
    return f'<div class="chapter"><ul class="toc">{"".join(toc)}</ul>{body}</div>'
