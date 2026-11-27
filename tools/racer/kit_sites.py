"""Where the Track Kit's error messages come from (R82 M7): every message the kit's modules can raise or report, read out of
their source with `ast`, as a template ("face {}: material {} has no ktrk_rgb"), and the cart's own refusal names, read out
of its Zig. kit_errors.py gives each its fix; test_racer_kit_manual.py checks that every site has an entry and every entry
a site, so a new message cannot ship without a line in the manual.
"""

from __future__ import annotations

import ast
import re
from pathlib import Path
from typing import Final

TOOLS = Path(__file__).resolve().parents[1]
ZIG = TOOLS.parent / "apps/zig/scenes/racer"
# the modules an author's file goes through: the export, the converters, their checks, the pack builder
MODULES: Final = ("ktrk", "kit_export", "kcar_export", "ktrk_check", "budget", "kit", "trackc", "mood", "carcheck", "carc", "panc",
                  "mood_props", "trackpack")
ERRORS: Final = {"KitError", "ConvertError", "CarError", "PanError", "PackError", "ValueError"}


def _template(node: ast.expr) -> str | None:
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.JoinedStr):
        return "".join(v.value if isinstance(v, ast.Constant) else "{}" for v in node.values)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):  # "a" + (f"b" if x else "")
        left = _template(node.left)
        return None if left is None else left + "{}"
    return None


def _messages(node: ast.AST) -> list[str]:
    """A raise of one of ERRORS with a message, or a list of messages appended / returned (the validators)."""
    out: list[str] = []
    if isinstance(node, ast.Raise) and isinstance(node.exc, ast.Call) and node.exc.args:
        f = node.exc.func
        if (f.id if isinstance(f, ast.Name) else getattr(f, "attr", "")) in ERRORS:
            out.append(_template(node.exc.args[0]) or "")
    elif isinstance(node, ast.Call) and getattr(node.func, "attr", "") == "append" and node.args:
        t = _template(node.args[0])
        out += [t] if t and " " in t else []
    elif isinstance(node, ast.Return) and node.value is not None:
        out += _returned(node.value)
    elif isinstance(node, ast.ListComp):
        out += _returned(node.elt)
    return out


def _returned(v: ast.expr) -> list[str]:
    """The messages in a returned value: a list of them, one, or either branch of `a if c else b`."""
    if isinstance(v, ast.List):
        return [t for e in v.elts for t in _returned(e)]
    if isinstance(v, ast.IfExp):
        return _returned(v.body) + _returned(v.orelse)
    t = _template(v) if isinstance(v, (ast.JoinedStr, ast.BinOp)) else None
    return [t] if t and " " in t else []


def sites() -> dict[str, list[str]]:
    """module -> its message templates, each once (an empty template: a message built elsewhere, re-raised)."""
    out: dict[str, list[str]] = {}
    for m in MODULES:
        tree = ast.parse((TOOLS / "racer" / f"{m}.py").read_text())
        found = [t for node in ast.walk(tree) for t in _messages(node)]
        out[m] = [t for t in dict.fromkeys(found) if t]
    return out


def _error_set(file: str, name: str) -> set[str]:
    m = re.search(rf"pub const {name} = (?:error\{{([^}}]*)\}})", (ZIG / file).read_text())
    return {e.strip() for e in m.group(1).split(",") if e.strip()} if m else set()


def cart_names() -> set[str]:
    """Every reason the cart logs for a refused file: the parsers' error names, the loaders' and the scan's."""
    names = _error_set("trk.zig", "Error") | _error_set("carfile.zig", "Error") | _error_set("panofile.zig", "Error")
    names |= {"BadPack", "ReadFailed", "TooBig"}  # library.Fail, cars.Fail, pano.Fail
    why = re.search(r"pub const Why = enum \{([^}]*?)\n\n", (ZIG / "refusals.zig").read_text())
    names |= {w.split(",")[0].strip() for w in why.group(1).splitlines() if w.strip() and not w.strip().startswith("//")} if why else set()
    return names
