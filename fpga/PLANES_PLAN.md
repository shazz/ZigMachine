# FRESCO: cutting the cost of compositing planes (design study, 2026-10-18)

> **Status (perf/fresco-linemajor):** ranks 1 and 2 are built. W64 is a run-time switch
> (`glass run --fw-opt=2`, decisions.md 2026-10-18), off until the board proves it. Line-major
> groups follow a wider rule than §3's: every run of consecutive handler-free planes, not only
> the planes below the first handler plane, since the carts this plan targets have a handler on
> their lowest plane (overscan flicker, rasters) and §3's group is empty there. Option 3 applies
> when a group is the top layer.

Read-only study on `integrate/2026-10-17` (04655ae1, perf/fresco-probe merged). Inputs:
`BENCH_REPORTS.md` (board v6, posted=0), `review/PERFORMANCE_REVIEW.md` §8, the RTL in
`rtl/video/`, `soc/zm_video_axi.py`, `cycles/vseq.c` / `vplan.c` / `vdirty.c`, `machine/video.zig`,
and the probe's analysis (`cycles/vcal.c`, `vstat.c`). Numbers are sys cycles (100 MHz) unless
said; comp runs at 125 MHz (0.8 sys cycle per comp clock). No sim or Vivado was run.

## 1. Where a line-pass's ~4.2 K cycles go

The measured frame costs (`BENCH_REPORTS.md` "Frame cost by planes"): empty frame 0.157 Mc, a
static plane +0.33 Mc, a fully redrawn plane +0.52 Mc for the first and +1.16-1.19 Mc for each
further one (4,140-4,250 per line on 280 lines). Built from the RTL, a non-first PLANE pass with
`mix` on a covered line (`zm_video_pass.v` IDLE→LOAD→PAINT→MIX→STORE, strictly serial) is:

| Phase | What moves | Cycles | Why |
|---|---|---:|---|
| issue | CSR cmd write, toggle sys→comp, `take` | ~30 | `zmv_cmd` is an 18-cycle store; 2-3 clocks each way (`zm_video_cdc.py`) |
| LOAD PFB | 400 × 64-bit beats, 25 bursts of 16 | ~480 | reads pipeline (AR issued back to back), ~60-80 first-beat latency, 1 beat/clock after |
| LOAD picture | 400 beats | ~480 | **serial with the PFB load**: `ZMVideoAXI` grants one request at a time (`~active`), and the second `ReqCross` only leaves once the first is acked, so the latency is paid twice |
| fetch | 320 B = 40 beats | ~110 | one burst, mostly latency |
| PAINT | 320 columns | ~265 | 1 column a comp clock, 3-stage pipe (`zm_video_paint.v`); 400 cols + 16-clock `DIV` for fullscreen |
| MIX | 400 pairs | ~325 | 1 pair a comp clock, 4 deep (`zm_video_mix.v`) |
| STORE PFB | 400 beats as **800 × 4-byte W beats** (WR32), 50 bursts of 8 | ~880 | one W beat a sys clock at best, AW issued ahead (`ahead`), then `b_out == 0` |
| STORE picture | 800 W beats | ~880 | serial with the PFB store (`WritePortCross`: one burst end to end) |
| done | `st_done` needs `wr_busy` low; READY echo | ~40 | so pass N+1 never overlaps pass N (`cmd_ready = !busy`) |
| **total** | | **~3,500** | |

The remaining ~15 % to the measured 4,150: the scanout steals HP1 first (400 beats every 2,640
cycles, ~15 % of the port) and DDR latency/refresh. So **row I/O is ~2,700 of ~3,500 (≈78 %)**,
the 32-bit write channel alone ~1,760, and painting + mixing only ~600: the compositor spends
most of a pass moving the same row in and out of DDR because the order is plane-major.
Uncovered lines (the 80 border lines of a normal plane) still cost LOAD PFB + LOAD picture + MIX
+ STORE picture ≈ 2,200. The first layer with CLEAR fusion (no loads) measures 1,850/line.

Checked against the probe's claims: `b_out` is 6 bits, so "63 outstanding writes" is the counter's
width, not a throughput (`ahead` lets W run only behind issued AWs, and the port accepts 8
commands); READY = STORE done, yes; serial phases, yes. The one number the RTL cannot give is
the W channel's real rate under the AFI's expansion of 4-byte beats; the probe's VCAL
(`R = MIX2 − MIX1`, `W` from FILL1 − MIX1 + R) settles it on the board before anything is built.

What the static plane's 0.33 Mc is: not FRESCO at all. `vd_line` compares 320 B per line and plane
(`cmpcpy`): ~20 D$ line misses at 48 cycles ≈ 1,000-1,200 cycles a line, 280 lines → 0.33 Mc of
ZIGGY time. That is the cost of a line skipped outright (an all-static frame, the bench's
`fr.static`). On a mixed screen it is worse: a line is skipped for every layer or for none (`ver[y]`
bumps when any plane's row y moved), so a static plane beside a fully redrawn one is composited on
every line the redrawn one covers and costs a full pass, ~0.85-1.17 Mc, its compares hidden under
the first layer's pass. "Static" is only cheap when the whole line is static.

A caveat on the per-line figures: the bench's `touch()` pokes only the 200 covered rows, so with the
planner ON the 80 border lines are skipped and the per-pass costs read 2,585 (first layer) and
~5,800 (non-first) instead of 1,850 and 4,150 on 280 lines; `vadapt` may have switched during the
samples. Neither basis fits a one-W-beat-a-clock model for both numbers, which is why VCAL (no
planner, line 0 only) must give R and W before W64's payoff is quoted (±40 % either way). The case
for line-major does not depend on it: the bytes it removes scale with the plane count whatever
the per-byte rate.

## 2. Options, savings, cost, risk

Savings are per frame against today's 1.17 Mc per redrawn plane (R = redrawn planes, S = static).

| # | Option | Saving (Mc/frame) | LUT / BRAM | Risk |
|---|---|---|---|---|
| 1 | **W64**: 8-byte write beats (`hp_cfg` bit 1) with HP1's AFI write channel set 64-bit (`mw.l 0xf8009014 0xf00` instead of `0xf01`, PL idle) | −0.22 per redrawn plane and −0.25 on the first layer (800 W beats fewer a line); R=2: −0.45, R=4: −0.9 | 0 / 0 | the 2026-10-03 "upper words lost" was 8-byte beats into a 32-bit channel; must be proven by hp-test on HP1 then bdiag mode 3 before anyone leans on it |
| 2 | **Line-major for the handler-free group** (§3): all planes of line y while the row stays in the line buffer + accumulator; one load/store pair a line | per extra redrawn plane: 0.20 instead of 1.17 (−0.97). R=1: 0; R=2: −0.97; R=3: −1.94; R=4: −2.9 | ~30-50 / 0 | exactness (§3 gives the rule and the proof); vdirty unchanged in principle |
| 3 | **No PFB row store on the board** (only with 2, and only when the group is the whole plane phase: a plane-major layer above it LOADs the row the group stored). No ZigOS or cart code reads the PFB (`zigos.physical_framebuffer` is set and never used; checked over libs/, apps/, rom/); on the board only the debug dump (`board_shot --what pfb`) and hashed sim frames do | −0.25 (280 × 880 WR32; −0.12 under W64) whatever R | ~5 / 0 | none on pixels (the picture is what is shown); keep it on in sims and hashed frames |
| 4 | **Hardware dirty bitmap** (§4): CPU stores (the snoop) and CHISEL writes set a bit per 4 KB VRAM granule; palette-bank and register-word touched masks | −0.33 per static plane on all-static frames (the compares go), −6 K for the palettes; on mixed screens the compares were hidden, so the gain is the planner staying ON always (vadapt's OFF/PROBE frames go) and ZIGGY time back for the cart | ~150-250 LUT, ~350 FF / 0 | a writer the taps miss = silent stale rows: the writer list must be closed (§4) |
| 5 | **Per-line fill table**: BG passes record the line's colour instead of storing the PFB row; the first layer fills from it (CLEAR fusion for global-handler carts) | −0.25 (BG stores) −0.13 (first-layer loads) ≈ −0.38 on every raster cart (global handler, no BEAM) | ~40 / 1 RAMB18 | BEAM lines keep the store + load (a flag a line) |
| 6 | **Uncovered-line skip** (firmware only, today): a non-first normal/scroll/medium plane's pass on the 80 lines it does not cover is a no-op when every palette alpha ∈ {0, 255} and BACKGROUND's is 255 (over() is then idempotent, exact) | −0.18 per such plane in plane-major; ~−0.03 once 2 lands (the fold alone) | 0 / 0 | the alpha check reads 4 KB a frame (~6 K cycles) until 4 makes it free |
| 7 | **Double-buffered rows + 2 requests in flight**: load line y+1 while y stores | ≤ −0.28 per redrawn plane (hides latency; the bus floor of ~2,900 a pass stays) | ~150-200 / +2 RAMB36 (LB and acc doubled) | changes the DMA's one-request contract and `WritePortCross`; superseded by 2 |
| 8 | **Hardware pass sequencer** for handler-free lines | −0.02 per plane (the ~80-cycle issue gap); frees ZIGGY only for firmware work (audio bridge, input, cursor, next frame's planner), never for `frame()` | ~300 / 0 | carts draw in place into the LFBs the compositor reads, so the next `frame()` cannot overlap; low value |

Combined, for a 4-plane cart with 2 redrawn + 2 static and no plane handler, today every covered
line is composited four times: 0.52 + 3 × 1.17 + 0.16 ≈ 4.2 Mc (the bench's `dirty.p4` shape,
2 VBLs); with 1-3: the line costs FILL + 4 × 780 + one picture store ≈ 4,300 → 1.2 + 0.16 ≈ 1.4 Mc
(60 fps with W64, 1.2 Mc). That is the point: on a mixed screen line-major is what makes a static
plane cheap, the bitmap only makes the planner free. Nothing above needs a LUT cut: 1-6 add under
~350 LUT to 14,888 (≈ 86.5 %, perf/ziggy-posted's buffer included in the baseline) and 0-1 RAMB18; 7 would add 2 RAMB36 (39 → 41 of 60) and is not recommended.

### Ranking

1. **W64** (0 LUT, measure-first): hp-test on HP1 with `WRCHAN_CTRL 0xf00`, then bdiag mode 3,
   then VCAL. If it holds, every row store halves at once, including after 2.
2. **Line-major group + no PFB store on the board** (2 + 3): the structural fix; the bytes moved
   per line stop scaling with the number of planes.
3. **Hardware dirty bitmap** (4): the static-plane cost, and the planner always on.
4. **Per-line fill table** (5) for raster carts; **uncovered-line skip** (6) can land now in
   firmware, independently, and shrinks to a mix-skip once 2 lands.
5. Not now: 7 (the bus floor remains, 2 removes the bytes instead), 8 (little to free).

## 3. Line-major: the exact rule, not a detector

`video.zig` is plane-major: `clear()` (G(y) + BG(y) for all y), `frame()`, then plane p's handler
H_p(y) and pass for all y, p = 0..3. A pass reads live state (its palette, HSCROLL in scroll mode,
RESOLUTION in medium, RES_FLICKER in overscan, the LFB bytes) plus what LATCH took. Interleaving
H_p and H_q line by line changes what a pass sees whenever a handler writes what another plane's
pass reads (another plane's palette or LFB bytes, RESOLUTION, RES_FLICKER, the registers LATCH
takes), or when two handlers talk through cart RAM. `ZM_LINE_MAJOR` moved `frame()` too and broke
badflicker and equinox (`tools/video_order.py`). LFB stores are not snooped, so a runtime detector
cannot be complete, and a frame found wrong cannot be redone (handlers cannot be re-run).

**The rule:** keep `vseq_clear` (G and BG, before `frame()`) exactly as it is. In the plane phase,
the enabled planes **before the first plane with an HBL handler** (`vd_plan`'s `handler_plane()`
already carves the frame this way) form the *group*: no cart code runs between their passes, so
every live read sees `frame()`'s final state in either order, LATCH of each sees the same registers,
and the line buffer and accumulator already persist across passes within a line (nothing clears
them). The group is composited line-major; the handler plane and everything above it stay
plane-major, loading the PFB row the group stored. A handler plane is never in a group, not even as
the last plane: its handler may write RESOLUTION, RES_FLICKER or a lower plane's palette or LFB
per line, which the lower plane would see at line y in one order and not the other. 124 of the 160
scene entries in `apps/zig/scenes` have no plane handler at all: their whole plane phase is the group. badflicker and equinox
select plane-major by the rule.

**RTL** (`zm_video_pass.v`, `zm_video_comp.v`, `soc/zm_video_csr.py`): two command bits, `hold`
(skip LOAD: the LB and accumulator hold line y) and `keep` (skip STORE). A group's line: plane g0
with `first` and `hold = 0` (LOAD PFB, or FILL under CLEAR fusion; no picture load), `keep = 1`;
middle planes `hold = keep = 1`; the last `hold = 1, keep = 0` (STORE PFB if any plane painted the
line, and the picture). `fill` goes on g0's pass only: IDLE takes FILL whenever `fill` is set, which on a held pass would
repaint the CLEAR colour over what the planes before painted. `dirty` and a new `filled` bit become
sticky across held passes (both reset only on a non-`hold` take) and feed `st_pfb`, else a line no
plane covers would never store its fill. A `keep` pass has no STORE, so READY follows MIX. `mix_first` is still
the line's first fold. Option 3 is a third bit (or a mode CSR) that drops `st_pfb` on the board.
About 10 lines of RTL; no new memory, no new bus behaviour.

**Firmware** (`vseq.c`, `bmain.c`, `vplan.c`): `vseq_group(e, mask)`: LATCH each plane of the
group (in index order, as plane-major would right before its first pass; no handler ran in between,
so the registers are the same), then per line: `vd_line` once (the group is the first layer; a
skipped line skips every plane), then the planes' passes with the bits above. `vseq_plane` serves
the planes above the group as today. `tools/cycles_csr.py` regenerates the cmd header (ABI: the
cmd CSR grows by 2-3 bits; the sim and the board firmware rebuild together). The sim keeps
plane-major on hashed frames (`bmain` already forces full composites there) so the per-plane PFB
hash contract holds; the line-major path needs its own proof (below).

**Tests.** (a) The RTL testbench replays recorded frames pass by pass (`rtl/video/TESTING.md`):
add a line-major replay of the same frame for every cart whose group is the whole plane phase; the
final PFB and the picture must equal the plane-major replay's bit for bit. (b) The board-SoC sim
hashes the picture (the vmix oracle, `tools/video_dump/vmix.c`) against the native host for
tutorial, scroll, empire and a 3-4 plane cart, with `ZM_VSEQ_CHECK` on. (c) Break mutants
(`ZM_RTL_BREAK=1`, test_vdirty style): a pass that takes `hold` but reloads the row (must be
caught by a frame whose lower plane painted it); `dirty` or `filled` not sticky (a line painted by g0 only, or covered by no plane,
is then never stored); `fill` taken on a held pass (the CLEAR colour over g0's paint); `mix_first` set on a middle plane (the fold restarts from the tube); the rule
ignored, forcing badflicker's handler plane into the group (must mismatch, as `video_order.py`
predicts); option 3 left on in a hashed frame (the PFB hash must fail). (d) Pixel-exactness stays
with `scene_hash.mjs` for the PFB per plane and the picture oracle for the board.

## 4. Hardware dirty bitmap (option 4)

VRAM is 1 MiB (`OFF_VRAM` .. `OFF_PFB`): 256 granules of 4 KB, a 256-bit set-only register. Two
taps: the snoop (`soc/zm_video_snoop.py` already has `off = adr − vbase` and the region decode; add
`vram_sel` and `granule = (off − OFF_VRAM/4) >> 10`), and CHISEL's write addresses on HP2
(`soc/zm_blit_hp.py` AW, folded into the region the same way). Also 4 palette-bank bits and 32
register-word bits (`cpu_sel` and `pal_idx[9:8]` give them for free). Read-and-clear through the
CSR bus (8 + 2 words), once per frame in `vd_plan`: granules → line ranges per plane from base and
stride (a few hundred cycles); a touched palette bank re-reads that bank only. `vd_line` then
compares nothing, and `vadapt` is retired (the plan is free). Writers that must be covered or
declared: the CPU (misaligned-trap byte stores included: they are CPU stores), CHISEL, and the ARM
(cart load, disk streaming, mailbox): the firmware calls `vd_unknown` on every ARM-side event,
as it does at boot. BARD's HP3 reaches the whole cart window (`zm_sound_cpu.py`), so its S2C mirror must be shown never
to land in VRAM, or HP3 gets a third tap. Break test:
a mutant without the CHISEL tap on blitter_demo must mismatch; without the trap-store path on ics.

## 5. What the probe must confirm before building

`VCAL` R and W on the board (the W channel's real rate; whether W64 halves it), the
ready/drain/painted split per frame on a 3-plane cart, `DMA_BUSY` against `COMP_BUSY` (bus-bound
or latency-bound), and the sticky underrun bit. If W turns out far above 880 a row, option 1 and
option 2 both gain proportionally; if R dominates, the serial double load (two `ReqCross`
round trips) is a cheap 2-in-flight fix inside `zm_video_rowio.v` that 2 makes unnecessary.
