"""Insert the study's roadmap row under the Open table's header (idempotent)."""
from __future__ import annotations

from pathlib import Path

p = Path("docs/ROADMAP.md")
s = p.read_text()
row = (
    "| P1 | In progress (branch `study/lut-diet`, on `feat/desk-border-colour` + `study/ziggy-big-reads`) | "
    "LUT / slice diet of the 7010 (every feature kept) so the ZIGGY `fast` + `prefetch` reads fit | SoC / KESTREL | "
    'Matt 10 Nov: "find miracles". The desk build is 16,958 LUT at synth (96.4 %), 4,400/4,400 slices, closed only '
    "by a re-route; `fast`/`prefetch` fail placement. Study fpga/review/LUT_DIET_STUDY.md: the breakdown (hierarchy, "
    "control sets), every candidate measured OOC, what was applied, the (a) desk + diet + fast + prefetch bitstream "
    "and the board check. Artefacts prototypes/lut_diet/ | agent |\n"
)
marker = "|---|---|---|---|---|---|\n"
if "study/lut-diet" not in s:
    i = s.index(marker) + len(marker)
    p.write_text(s[:i] + row + s[i:])
print("ok")
