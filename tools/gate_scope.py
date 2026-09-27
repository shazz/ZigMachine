"""Which screen harnesses must a change run? The classifier behind a narrowed gate.

Reads `git diff --name-status --no-renames` lines on stdin and prints ONE line:
`FULL` or the exact gate tags to run (possibly empty). Reasons go to stderr.

Only the per-screen HARNESSES are ever narrowed: build.sh still rebuilds every
cart and disk and runs every cross-cutting check. So the only question here is
"can this file change what some other screen's harness sees?" Every rule errs
towards FULL, and an unknown path is FULL.

Why a cart's own docs/demo-<tag>.wasm is evidence: the pre-push hook refuses a
push whose docs/ differ from a rebuild of its source, and the base it diffs
against passed the same check. So a source change that alters cart Y's bytes
(a scene file shared with Y, say) shows up as docs/demo-Y.wasm in the diff, and
Y's harnesses are selected -- or the push fails the docs check.
"""
from __future__ import annotations

import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

GATE_LINE = re.compile(r"^gate(?:_timed)? ([A-Za-z0-9_]+) (.*)$")
MJS_REF = re.compile(r"apps/([A-Za-z0-9_]+\.mjs)")
IMPORT = re.compile(r"""from\s+["']\./([A-Za-z0-9_]+\.mjs)["']""")
CART_NAMES = re.compile(r"const cart_names = \[_\]\[\]const u8\{(.*?)\};", re.S)
CART_NAME = re.compile(r'"demo-([a-z0-9_]+)"')
DYNAMIC_CART = re.compile(r"demo-\$\{")


@dataclass
class Repo:
    """What the classifier knows about the tree: carts, gate lines, harness text."""

    carts: set[str]
    gates: list[tuple[str, str]]  # (tag, command line), in build.sh order
    closure: dict[str, str] = field(default_factory=dict)  # harness -> its text + imports'

    @property
    def tags(self) -> list[str]:
        return list(dict.fromkeys(t for t, _ in self.gates))


def read_closure(root: Path, name: str, seen: set[str] | None = None) -> str:
    """A harness's source plus every ./x.mjs it imports, transitively."""
    seen = set() if seen is None else seen
    if name in seen or not (root / "apps" / name).is_file():
        return ""
    seen.add(name)
    text = (root / "apps" / name).read_text(errors="replace")
    return text + "".join(read_closure(root, dep, seen) for dep in IMPORT.findall(text))


def load(root: Path) -> Repo:
    block = CART_NAMES.search((root / "build.zig").read_text())
    carts = set(CART_NAME.findall(block.group(1))) if block else set()
    gates = []
    for line in (root / "build.sh").read_text().splitlines():
        m = GATE_LINE.match(line)
        if m:
            gates.append((m.group(1), m.group(2)))
    repo = Repo(carts, gates)
    for tag, cmd in gates:
        for mjs in MJS_REF.findall(cmd):
            repo.closure[tag] = repo.closure.get(tag, "") + read_closure(root, mjs) + cmd
    return repo


def tags_using(repo: Repo, needle: str) -> set[str]:
    """Gate tags whose harness (or its imports, or its arguments) mention `needle`."""
    return {t for t, text in repo.closure.items() if needle in text}


def cart_tags(repo: Repo, cart: str) -> set[str]:
    """The harnesses a change to one cart's bytes can reach."""
    hit = {t for t in repo.tags if cart in t}  # build.sh --only's substring rule
    hit |= tags_using(repo, f"demo-{cart}.")  # e.g. digital_solution runs demo-big_demo
    hit |= {t for t, text in repo.closure.items() if DYNAMIC_CART.search(text)}
    return hit


def component_tags(repo: Repo, name: str) -> set[str] | None:
    """apps/zig/scenes/<name>... or assets/screens/<name>/: None means FULL."""
    carts = [c for c in repo.carts
             if c == name or c.startswith(name + "_") or name.startswith(c + "_")]
    if not carts:
        return None  # catalog.zig, menu.zig, demo.zig...: registration or shared
    out: set[str] = set()
    for c in carts:
        out |= cart_tags(repo, c)
    return out | tags_using(repo, f"screens/{name}/") | tags_using(repo, f"scenes/{name}")


def apps_file_tags(repo: Repo, path: str) -> set[str] | None:
    """A top-level apps/ file (a harness, a helper, a fixture): who reads it?"""
    base = path.split("/", 1)[1]
    users = tags_using(repo, base)
    if users:
        return users
    return None  # read by no gate harness: a cross-cutting helper, or unknown


def classify(repo: Repo, status: str, path: str) -> set[str] | None:
    """The gate tags one changed path needs, or None for the full gate."""
    parts = path.split("/")
    if path.endswith(".md") or path.startswith("docs/ports/"):
        return set()  # prose: the doc generators' checks are cross-cutting
    if parts[0] == "docs" and path.startswith("docs/music/"):
        return set() if status == "A" else None  # a new tune breaks no one
    m = re.fullmatch(r"docs/demo-([a-z0-9_]+)\.(wasm|zmd)", path)
    if m:
        return cart_tags(repo, m.group(1)) if m.group(1) in repo.carts else None
    if path.startswith(("apps/zig/scenes/", "apps/zig/assets/screens/")) and len(parts) > 3:
        return component_tags(repo, parts[3].split(".")[0])
    if parts[0] == "tools" and len(parts) > 2 and parts[1] in repo.carts:
        return cart_tags(repo, parts[1]) | tags_using(repo, f"tools/{parts[1]}/")
    if parts[0] == "apps" and len(parts) == 2:
        return apps_file_tags(repo, path)
    return None


def scope(repo: Repo, lines: list[str]) -> tuple[list[str] | None, list[str]]:
    """(the gate tags in build.sh order, or None for FULL; the reasons)."""
    wanted: set[str] = set()
    reasons = []
    for line in filter(None, (s.strip() for s in lines)):
        status, path = line.split("\t", 1) if "\t" in line else ("M", line)
        got = classify(repo, status[0], path)
        if got is None:
            reasons.append(f"shared or unknown: {path}")
        else:
            wanted |= got
            reasons.append(f"{path} -> {' '.join(sorted(got)) or '(no harness)'}")
    if any(r.startswith("shared") for r in reasons):
        return None, [r for r in reasons if r.startswith("shared")]
    return [t for t in repo.tags if t in wanted], reasons


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
    tags, reasons = scope(load(root), sys.stdin.read().splitlines())
    for r in reasons:
        print(f"  {r}", file=sys.stderr)
    print("FULL" if tags is None else " ".join(tags))
    return 0


if __name__ == "__main__":
    sys.exit(main())
