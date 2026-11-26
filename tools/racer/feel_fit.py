"""Fit feel.py's ARCADE classes to the 32X's measured behaviour (R82). LOCAL INPUT: the targets file is measured from
the 32X and stays out of git (prototypes/, see FEEL.md); this tool, the method and the fitted curves (ours) are committed.

Targets JSON: {"classes": [{"top": km/h, "accel": {"<km/h>": ticks}, "coast": {"<km/h>": ticks}, "off_full": km/h,
"off_half": km/h}, ...]} in OUR ticks (30 Hz). The fit keeps the control speeds and each class's top, and moves the
acceleration values (net), then the coast-down values (drag), then the off-road constant, by coordinate descent on the
integer twin (feel.run), minimising the squared relative time error at every target speed (or the speed error off-road).

    python3 tools/racer/feel_fit.py <targets.json>            # the residual table of feel.CLASSES
    python3 tools/racer/feel_fit.py <targets.json> --fit      # ... and the refitted Klass literals to paste into feel.py
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import replace
from pathlib import Path
from typing import Final

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from racer import feel  # noqa: E402

Target = dict[str, object]
TICKS: Final = 900
STEPS: Final = (4.0, 1.0, 0.25)


def _times(t: Target, key: str) -> dict[int, float]:
    raw = t[key]
    if not isinstance(raw, dict):
        raise ValueError(f"targets: '{key}' must be an object")
    return {int(k): float(v) for k, v in raw.items() if float(v) > 0}


def _off_eq(b: feel.Block, off: int) -> float:
    return feel.run(b, TICKS, b.top, off=off)[-1] * feel.KMH / 65536


def residuals(k: feel.Klass, t: Target) -> dict[str, float]:
    """Relative time error per target speed ('a<km/h>' accelerating, 'c<km/h>' coasting) and the off-road speed error."""
    b = feel.Block.of(k)
    up, down = feel.run(b, TICKS), feel.run(b, TICKS, b.top, held=False)
    out: dict[str, float] = {}
    for kmh, want in _times(t, "accel").items():
        got = feel.ticks_to(up, kmh) or TICKS
        out[f"a{kmh}"] = (got - want) / want
    for kmh, want in _times(t, "coast").items():
        got = next((i + 1 for i, s in enumerate(down) if s * feel.KMH <= kmh << 16), TICKS)
        out[f"c{kmh}"] = (got - want) / want
    for key, off in (("off_full", feel.OFF_FULL), ("off_half", feel.OFF_HALF)):
        want = float(t[key])  # type: ignore[arg-type]  # WHY: a JSON number, checked by float()
        out[key] = (_off_eq(b, off) - want) / want
    return out


def _cost(k: feel.Klass, t: Target, prefix: str) -> float:
    return sum(v * v for name, v in residuals(k, t).items() if name.startswith(prefix))


def _nudge(k: feel.Klass, field: str, i: int, d: float) -> feel.Klass:
    if field == "off":
        return replace(k, off=max(0.5, k.off + d))
    pts = list(getattr(k, field))
    pts[i] = (pts[i][0], max(0.5, pts[i][1] + d))
    return replace(k, **{field: tuple(pts)})


def _descend(k: feel.Klass, t: Target, field: str, idx: range, prefix: str) -> feel.Klass:
    for step in STEPS:
        better = True
        while better:
            better = False
            for i in idx:
                for d in (step, -step):
                    c = _nudge(k, field, i, d)
                    if _cost(c, t, prefix) < _cost(k, t, prefix):
                        k, better = c, True
    return k


def fit(k: feel.Klass, t: Target) -> feel.Klass:
    k = _descend(k, t, "net", range(len(k.net) - 1), "a")
    k = _descend(k, t, "drag", range(len(k.drag)), "c")
    return _descend(k, t, "off", range(1), "off")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("targets", type=Path)
    ap.add_argument("--fit", action="store_true")
    a = ap.parse_args(argv)
    targets = json.loads(a.targets.read_text())["classes"]
    if len(targets) != len(feel.CLASSES):
        print(f"feel_fit: {len(targets)} target classes, feel.py has {len(feel.CLASSES)}", file=sys.stderr)
        return 1
    for k, t in zip(feel.CLASSES, targets, strict=True):
        k = fit(k, t) if a.fit else k
        r = residuals(k, t)
        print(k.name, " ".join(f"{n}:{v * 100:+.1f}%" for n, v in r.items()))
        if a.fit:
            print(f"    {k!r},")
    return 0


if __name__ == "__main__":
    sys.exit(main())
