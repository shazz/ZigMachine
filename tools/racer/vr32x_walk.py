"""LOCAL ONLY: the racing-line WALK on an imported 32X track's asphalt (tools/racer/vr32x_line.py has the shortest-lap
alternative; the importer keeps the longer good one).

Step by step along the road, straightest first: a fan of rays from the walker finds the roads ahead (runs of headings whose
ray stays on asphalt for LOOK units). Where there are two (a fork), a way whose asphalt ends without reaching the start
(a stub, a dead-end apron: Cells.open_way, with the road just behind cut) is not taken. A walk follows the road where a
shortest lap would cut across (a lollipop: Acropolis' hook), and never turns back (the fan is +-1.4 radians).
"""

from __future__ import annotations

import math

from racer.vr32x_cells import Cells
from racer.vr32x_geom import Bins
from racer.vr32x_line import COVER, STEP, LineError, Pt, Station, _height, _station, coverage

LOOK = 4.0  # units a way's ray must run on asphalt
FAN, FAN_STEP = 7, 0.2  # rays at -1.4 .. 1.4 radians
GAP = 2  # blocked rays between two runs for them to be two roads
BACK, CUT = 16, 6.0  # the cut behind a fork: across the road 8 units back, 6 units each way


def _clear(bins: Bins, p: Pt, a: float) -> bool:
    y = p[1]
    for k in range(1, int(LOOK / STEP) + 1):
        h = _height(bins, p[0] + math.sin(a) * k * STEP, p[2] + math.cos(a) * k * STEP, y)
        if h is None:
            return False
        y = h
    return True


def _ways(bins: Bins, p: Pt, hd: tuple[float, float]) -> list[float]:
    """Headings of the distinct roads ahead, straightest first (one per run of clear rays: its middle)."""
    base, runs, last = math.atan2(hd[0], hd[1]), [], -99
    for i in range(-FAN, FAN + 1):
        if _clear(bins, p, base + i * FAN_STEP):
            if runs and i - last <= GAP:
                runs[-1].append(i)
            else:
                runs.append([i])
            last = i
    mids = sorted((r[len(r) // 2] for r in runs), key=abs)
    return [base + i * FAN_STEP for i in mids]


def _ahead(p: Pt, a: float, d: float) -> Pt:
    return (p[0] + math.sin(a) * d, p[1], p[2] + math.cos(a) * d)


def _pick(bins: Bins, cells: Cells, out: list[Station], p: Pt, hd: tuple[float, float], start: Pt) -> Station | None:
    widths = sorted(math.dist(s[0], s[2]) for s in out[-40:])
    width = widths[len(widths) // 2] if widths else 0.0
    ways = _ways(bins, p, hd)
    if len(ways) > 1 and len(out) > BACK:
        cut = cells.band([out[-BACK][1]], CUT)
        ways = [a for a in ways if cells.open_way(_ahead(p, a, 2.0), start, cut)] or ways[:1]
    base = math.atan2(hd[0], hd[1])
    for a in ways + [base + t for t in (0, 0.3, -0.3, 0.7, -0.7, 1.1, -1.1)]:
        st = _station(bins, p, (math.sin(a), math.cos(a)), width)
        if st:
            return st
    return None


def walk(bins: Bins, cells: Cells, start: Pt, heading: float, max_len: float = 2500.0) -> list[Station]:
    """A closed walk from `start` heading `heading` (radians, 0 = +z), or LineError."""
    hd, p, gone, out = (math.sin(heading), math.cos(heading)), start, 0.0, []
    while gone < max_len:
        st = _pick(bins, cells, out, p, hd, start)
        if st is None:
            raise LineError(f"the walk left the asphalt at {p[0]:.1f},{p[2]:.1f} after {gone:.0f} units")
        d = (st[1][0] - p[0], st[1][2] - p[2])
        n = math.hypot(*d) or 1.0
        h = (0.7 * hd[0] + 0.3 * d[0] / n, 0.7 * hd[1] + 0.3 * d[1] / n)
        hd, p, gone = (h[0] / math.hypot(*h), h[1] / math.hypot(*h)), st[1], gone + n
        out.append(st)
        if gone > 50 and math.dist(p, start) < STEP * 1.5:
            if coverage(bins, out) < COVER:
                raise LineError(f"a short loop ({gone:.0f} units)")
            return out
    raise LineError(f"the walk did not come back to its start in {max_len:.0f} units")
