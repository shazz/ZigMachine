"""Splits docs/TUTORIAL.md into steps and per-language blocks.

The markdown stays the single source of truth and stays readable on GitHub; this
module only recognises the structure the file already has:

  1. `# ` heading            -> the page title; prose until the first `## ` is the intro.
  2. `## Step N: title`      -> a step (step 8 uses a comma: `## Step 8, going further: ...`).
     any other `## `         -> a plain section ("Before you start", "Where next").
  3. `### Zig|C|Rust`        -> a language block inside a step. Any other `### `
                                inside a step is an error, so a typo fails the
                                build instead of silently vanishing from the page.
  4. A language block ends at the next `### `, the next `## `, a `---` rule, or the
     first column-0 bold lead-in (`**What you should see.**`) — which is what
     returns the checkpoint prose to the shared zone with no marker in the md.
  5. Prose before the first language block is `before`; after the last is `after`.
     A step with no language blocks (step 8) is shared-only.

Fenced code is tracked throughout, so a `---` or a `**bold**` line inside a
``` block cannot split a section.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

LANGS = {"Zig": "zig", "C": "c", "Rust": "rust"}
STEP_RE = re.compile(r"^## Step (\d+)[:,]\s*(.+)$")
LEAD_IN_RE = re.compile(r"^\*\*[A-Z][^*]*\.\*\*")
FENCE_RE = re.compile(r"^\s*```")


class TutorialFormatError(Exception):
    """docs/TUTORIAL.md broke the contract above."""


@dataclass
class LangBlock:
    lang: str  # "zig" | "c" | "rust"
    md: str


@dataclass
class Section:
    title: str
    before: str = ""
    after: str = ""
    number: int | None = None  # set for steps, None for plain sections
    langs: list[LangBlock] = field(default_factory=list)

    @property
    def is_step(self) -> bool:
        return self.number is not None

    @property
    def slug(self) -> str:
        if self.is_step:
            return f"step-{self.number}"
        return re.sub(r"[^a-z0-9]+", "-", self.title.lower()).strip("-")


@dataclass
class Tutorial:
    title: str
    intro: str
    sections: list[Section]

    @property
    def steps(self) -> list[Section]:
        return [s for s in self.sections if s.is_step]


def _outside_fence(lines: list[str]) -> list[bool]:
    """Per line: True when it is NOT inside a ``` fenced block."""
    out, fenced = [], False
    for line in lines:
        if FENCE_RE.match(line):
            out.append(not fenced)  # the opening fence itself is still outside
            fenced = not fenced
        else:
            out.append(not fenced)
    return out


def _joined(lines: list[str]) -> str:
    return "\n".join(lines).strip("\n")


def _split_langs(body: list[str], where: str) -> tuple[str, list[LangBlock], str]:
    """Body of a step -> (shared before, language blocks, shared after)."""
    free = _outside_fence(body)
    before: list[str] = []
    after: list[str] = []
    langs: list[LangBlock] = []
    cur: LangBlock | None = None
    for line, outside in zip(body, free):
        heading = re.match(r"^### (.+?)\s*$", line) if outside else None
        if heading:
            name = heading.group(1)
            if name not in LANGS:
                raise TutorialFormatError(
                    f"{where}: unknown '### {name}' — expected one of {', '.join(LANGS)}"
                )
            cur = LangBlock(LANGS[name], "")
            langs.append(cur)
            continue
        if cur is not None and outside and (LEAD_IN_RE.match(line) or line.strip() == "---"):
            cur = None  # back to shared prose for the rest of the step
        if cur is not None:
            cur.md += line + "\n"
        elif langs:
            after.append(line)
        else:
            before.append(line)
    for block in langs:
        block.md = _joined(block.md.splitlines())
    return _joined(before), langs, _joined(after)


def _section(header: str, body: list[str]) -> Section:
    step = STEP_RE.match(header)
    title = step.group(2).strip() if step else header[3:].strip()
    number = int(step.group(1)) if step else None
    where = f"step {number}" if step else f'section "{title}"'
    before, langs, after = _split_langs(body, where)
    return Section(title=title, before=before, after=after, number=number, langs=langs)


def parse(text: str) -> Tutorial:
    """docs/TUTORIAL.md source -> a Tutorial."""
    lines = text.splitlines()
    free = _outside_fence(lines)
    title = next((ln[2:].strip() for ln in lines if ln.startswith("# ")), "Tutorial")
    heads = [i for i, (ln, out) in enumerate(zip(lines, free)) if out and ln.startswith("## ")]
    if not heads:
        raise TutorialFormatError("no '## ' sections found")
    intro = _joined([ln for ln in lines[:heads[0]] if not ln.startswith("# ")])
    bounds = heads + [len(lines)]
    sections = [
        _section(lines[a], lines[a + 1:b]) for a, b in zip(heads, bounds[1:])
    ]
    return Tutorial(title=title, intro=intro, sections=sections)
