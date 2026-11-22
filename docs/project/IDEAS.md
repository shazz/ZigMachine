# Ideas Parking Lot

A place to capture interesting ideas, future exploration topics, and things worth revisiting.

## How to Use

- Add ideas with `/todo "your idea here"`
- Tag ideas for `/devil` review when you want adversarial analysis
- Prune regularly with `/todo --prune` to keep the list fresh
- Graduate ideas to issues when they're ready for implementation

---

## Active Ideas

### 2026-09-06 — Demoscene-style menu (Union demo remake)

Recode the Atari ST **Union demo** as a demoscene-style menu frame for ZigMachine — a
selector that launches the existing effect channels (now that there are many across topics).
Reuse effects and assets from shazz's own **Codef** HTML5 remakes, mirrored locally to
`assets/oldies/` via `tools/crawl_codef.sh`. The Codef `screens/<name>/screen.js` effects
(starfield, bobfield, scrolltext, 3d, texcopier, …) map closely to ZigMachine channels and
can be ported/reused rather than written from scratch.

**Reuse the menu:** Matt already built a nice menu for **UnionDemoCracktro** (mirrored at
`assets/oldies/UnionDemoCracktro/`) — start the demoscene-menu design from that rather than
inventing a selector.

**Source:** conversation with Matt (2026-09-06)
**Tags:** #ux #architecture #research
**Status:** parked

### 2026-09-20 — ZigMachine on an FPGA (the hardware half)

Split off from the native desktop host now tracked in `TODOS.md`. The HARDWARE
half of ZigMachine is plausible in fabric: planes, the shifter, the blitter and
the YM2149 are all proven on MiSTer, and a memory-mapped register ABI is
FPGA-shaped by nature — that is what the sealed machine already is.

**What blocks it: the carts are wasm, and an FPGA cannot run wasm.** It would
need a soft CPU — RISC-V, or a real 68000 core, which would have the pleasing
effect of turning the SNDH player's *emulated* 68000 into a real one — with the
carts compiled native and the register ABI kept as the contract between the two
halves. That contract surviving a change of CPU is the same claim the polyglot
carts and the desktop host make from their own directions.

**Source:** conversation with Matt (2026-09-20), alongside the desktop-host item
**Tags:** #hardware #research #someday
**Status:** parked

---

## Graduated (moved to issues/tasks)

_none yet_

---

## Dismissed (not pursuing)

_none yet_
