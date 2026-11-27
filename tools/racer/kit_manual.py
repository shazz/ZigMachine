"""The Track Kit manual's generated sections (R82 M7): docs/ports/kestrel_racing/TRACK_KIT.md holds three tables written from
the code, between `<!-- gen:NAME -->` and `<!-- /gen:NAME -->` markers, so they cannot drift from it:
  budget   the budget meter's rows (budget.rows, limits.py): label, limit, HARD or SOFT;
  mood     the mood panel's rows (mood_props.PROPS): property, default, meaning;
  errors   every message the kit can give, by stage, with its fix (kit_errors.py, kit_errors_car.py), and the cart's reasons.

    python3 -I tools/racer/kit_manual.py --write     rewrite the sections in place
    python3 -I tools/racer/kit_manual.py --check     exit 1 when the file is not what --write would make (test_racer_kit_manual.py)
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from racer import budget, kit_errors, kit_errors_car, limits, mood_props  # noqa: E402

MANUAL = Path(__file__).resolve().parents[2] / "docs/ports/kestrel_racing/TRACK_KIT.md"
STAGES = {"kit_export": "Export (the add-on's Export buttons, the live meter)", "ktrk": "Reading an export",
          "ktrk_check": "Validation (the converter's first stage)", "budget": "The budget check",
          "kit": "Conversion (palette, mood, cues, haze)", "trackc": "The track writer", "mood": "The mood block",
          "mood_props": "The mood panel (red rows)", "kcar_export": "Car Kit export", "carcheck": "Car Kit budget and shape",
          "carc": "The car writer", "panc": "The panorama writer", "trackpack": "The track pack builder"}


def _cell(s: str) -> str:
    return s.replace("|", "\\|").replace("{}", "...")


def budget_table() -> str:
    zero = budget.Meter(0, 0, 0, (0, 0), 0, 0)
    rows = [f"| {label} | {limit:,} | {'HARD' if hard else 'SOFT'} |" for label, _, limit, hard in budget.rows(zero)]
    rows += [f"| start grid slots | exactly {limits.GRID_SLOTS} | HARD |", "| checkpoints | strictly ascending | HARD |",
             "| a face (or a decal) with no area | none | HARD |",
             f"| the priced frame at R {limits.BENCH_R} (the converter's walk) | {limits.FRAME_MC} Mc | SOFT |"]
    return "| row | limit | kind |\n|---|---|---|\n" + "\n".join(rows)


def mood_table() -> str:
    rows = [f"| `ktrk_{p.key}` | {p.label} | {_cell(str(p.default)) if p.default not in (None, '') else '(the scene name)' if p.default is None else '(none)'} | {_cell(p.hint)} |"
            for p in mood_props.PROPS]
    return "| property | panel row | default | meaning |\n|---|---|---|---|\n" + "\n".join(rows)


def errors_table() -> str:
    out = []
    for module, entries in (kit_errors.TRACK | kit_errors_car.MORE).items():
        out.append(f"**{STAGES[module]}** (`tools/racer/{module}.py`)\n\n| message | fix |\n|---|---|")
        out += [f"| `{_cell(msg)}` | {_cell(fix)} |" for msg, fix in entries.items()]
        out.append("")
    out.append("**The cart** (its console `racer,track,refused,<NAME>,<why>` / `racer,car,refused` / `racer,pan,refused`, "
               "the select screen's refusals; the pack builder names the same)\n\n| reason | what it means, what to do |\n|---|---|")
    out += [f"| `{name}` | {_cell(fix)} |" for name, fix in kit_errors_car.CART.items()]
    return "\n".join(out)


SECTIONS = {"budget": budget_table, "mood": mood_table, "errors": errors_table}


def render(text: str) -> str:
    for name, make in SECTIONS.items():
        pat = re.compile(rf"(<!-- gen:{name} -->\n)(?:.*?\n)?(<!-- /gen:{name} -->)", re.DOTALL)
        if not pat.search(text):
            raise SystemExit(f"kit_manual: no <!-- gen:{name} --> section in {MANUAL}")
        text = pat.sub(lambda m, make=make: m.group(1) + make() + "\n" + m.group(2), text)
    return text


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args(argv)
    old = MANUAL.read_text()
    new = render(old)
    if a.write:
        MANUAL.write_text(new)
        return 0
    if new != old:
        print(f"kit_manual: {MANUAL} is stale: python3 -I tools/racer/kit_manual.py --write", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
