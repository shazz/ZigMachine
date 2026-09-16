"""A small generation-time syntax highlighter for the tutorial's code blocks.

Deliberately not Pygments: three C-family languages plus bash need about sixty
lines of regex, and a new build dependency for a cosmetic gain is not worth it
(see rules/shared/change-discipline.md on dependency hygiene). The failure mode
is an unstyled word, never wrong text — every token is HTML-escaped whether it
matched a rule or not.
"""
from __future__ import annotations

import re

from . import esc

KEYWORDS = {
    "zig": """align allowzero and asm async await break catch comptime const continue defer
        else enum errdefer error export extern fn for if inline noalias noinline nosuspend
        opaque or orelse packed pub resume return linksection struct suspend switch test
        threadlocal try union unreachable usingnamespace var volatile while anytype
        bool void type u8 u16 u32 u64 usize i8 i16 i32 i64 isize f32 f64 true false null undefined""",
    "c": """auto break case char const continue default do double else enum extern float for
        goto if inline int long register restrict return short signed sizeof static struct
        switch typedef union unsigned void volatile while _Bool true false NULL
        uint8_t uint16_t uint32_t int8_t int16_t int32_t u8 u16 u32 i8 i16 i32""",
    "rust": """as async await break const continue crate dyn else enum extern false fn for if
        impl in let loop match mod move mut pub ref return self Self static struct super
        trait true type unsafe use where while bool char str u8 u16 u32 u64 usize i8 i16
        i32 i64 isize f32 f64 Option Some None Result Ok Err""",
    "bash": """cd echo else fi for if in then do done export local return set source while case esac""",
}
KEYWORDS = {lang: set(words.split()) for lang, words in KEYWORDS.items()}

# Per-language comment syntax; everything else is shared by the four.
COMMENTS = {
    "zig": r"//[^\n]*",
    "c": r"//[^\n]*|/\*[\s\S]*?\*/",
    "rust": r"//[^\n]*|/\*[\s\S]*?\*/",
    "bash": r"\#[^\n]*",
}

TOKEN = r"""
      (?P<cm>{comments})
    | (?P<at>\#!?\[[^\]]*\])                       # Rust attributes: #[no_mangle]
    | (?P<pp>^[ \t]*\#[a-z]+)                      # C preprocessor: #define, #include
    | (?P<str>"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*')
    | (?P<num>0[xXbo][0-9a-fA-F_]+|\b\d[\d_]*(?:\.\d+)?\b)
    | (?P<word>[A-Za-z_][A-Za-z0-9_]*)
"""

ALIASES = {"sh": "bash", "shell": "bash", "console": "bash", "js": "c", "javascript": "c"}


def _compile(lang: str) -> re.Pattern[str]:
    return re.compile(
        TOKEN.format(comments=COMMENTS[lang]), re.VERBOSE | re.MULTILINE
    )


_CACHE: dict[str, re.Pattern[str]] = {}


def highlight(code: str, lang: str) -> str:
    """Code -> HTML with <span class="tok-*"> spans. Unknown languages pass through escaped."""
    lang = ALIASES.get(lang, lang)
    if lang not in COMMENTS:
        return esc(code)
    if lang not in _CACHE:
        _CACHE[lang] = _compile(lang)
    keywords = KEYWORDS[lang]
    out: list[str] = []
    pos = 0
    for m in _CACHE[lang].finditer(code):
        out.append(esc(code[pos:m.start()]))
        out.append(_span(m, keywords, code))
        pos = m.end()
    out.append(esc(code[pos:]))
    return "".join(out)


def _span(m: re.Match[str], keywords: set[str], code: str) -> str:
    kind = m.lastgroup
    text = m.group()
    if kind == "word":
        if text in keywords:
            kind = "kw"
        elif code[m.end():m.end() + 1] == "(":
            kind = "fn"
        else:
            return esc(text)
    return f'<span class="tok-{kind}">{esc(text)}</span>'
