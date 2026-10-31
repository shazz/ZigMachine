# Line-interleaved planes: would one fetch a line make FRESCO cheaper? (study, 2026-10-31)

**Recommendation: don't.** Interleaving the planes in memory (plane 0 row y, plane 1 row y, ...) merges
nothing by itself, and the merge it would allow in RTL saves only the per-fetch latency of the
held passes of a line-major group: **~0.01 Mc a frame for 2 planes, ~0.03 for 4** (normal planes,
latency prior 60 comp clocks; overscan x1.4), against a cart ABI change (planes stop being contiguous),
~150-250 LUT and a DSP at 89-94 % LUT. If the bench below shows the fetch latency is large, the
better fix is a **prefetch of the group's next plane** (no layout, no cart change, hides latency
AND beats), and if the gap is the sequencer's, a 2-deep command (PLANES_PLAN option 8's neighbour).
Fewer planes stays the lever: one plane less is 0.19-0.59 Mc.

Study only: no RTL, no cart, no shelf change. The one change is a board-only bench variant to settle
the last number (section 5). Cycles are sys (100 MHz) unless marked comp (125 MHz, 0.8 sys).

## 1. Where a plane line's fetch goes today (RTL)

- **Placement is already free.** Every plane has a latched base and stride (`zm_video_latch.v`);
  a line's address is `base + row * stride (+ HSCROLL in scroll mode)` (`zm_video_plane.v`,
  three pipeline stages and a DSP to meet 125 MHz); video.zig honours any stride the same way.
- **One request per plane per line.** `zm_video_fetch.v` asks one read burst (41 beats for a
  normal 320-byte line, 51 for an overscan 400) into a 256-beat (2 KB) fetch buffer; the plane FSM
  runs FETCH then PAINT, so the whole fetch is on the pass's critical path.
- **The DMA serialises requests.** `soc/zm_video_axi.py` grants one request at a time (scanout
  first), cuts it into 16-beat AXI bursts on 128-byte boundaries and pipelines THOSE (several ARs in
  flight), but holds `active` until the request's last beat. So the first-beat latency is paid once
  per request, i.e. once per plane per line, and never overlaps the next plane's.
- **The CDC adds both ways** (`soc/zm_video_cdc.py`): the request is a ReqCross comp -> sys, the
  beats an AsyncQueue sys -> comp (16 deep; the comp side drains faster than sys fills it).
- **One CPU command per pass.** Inside a group (`cycles/vseq_group.c`) every plane's pass of a
  line is its own command: `vseq_issue` waits READY (the previous pass done), DRAINED, writes CMD;
  the plane's geometry then waits its 4-clock `held` guard. PLANES_PLAN option 8 put this issue gap
  at ~80 sys a pass.
- **A held normal plane mixes all 280 lines.** On the 80 border lines it fetches and paints nothing
  but still MIXes its 800 pixels (406 comp), unless the planner skips the line. (Not a layout
  matter; noted because it is in the same increment as the fetch.)

## 2. Measurements

**RTL phase replay** (`tools/video_phase.py`, CXXRTL, `--line-major --nopfb`, tutorial f300: one
normal plane, 200 fetches; union_main f300: three overscan planes, 840 fetches):

| memory first-beat latency (comp) | 0 | 28 | 100 |
|---|---:|---:|---:|
| tutorial: fetch clocks / fetch | 41.0 | 68.0 | 140.0 |
| union_main: fetch clocks / fetch | 51.0 | 78.0 | - |

The fetch is exactly beats + latency: every clock of latency is paid on every plane line, nothing
overlaps it. Per held normal pass the RTL's own work is paint 329 + mix 406 + beats (41 at a beat
a comp clock, 51 at the board's beat a sys clock); per overscan pass 408 + 406 + 64.

**Board, the bench's frame tests** (`fpga/bench_results/2026-10-19_bench_w64boot.txt`, W64,
line-major; fr.dirty.pN = N normal planes, every row changed every frame, so N-1 held passes a
line): 0.422 / 0.611 / 0.799 / 0.995 Mc for 1..4 planes: **+0.189, +0.188, +0.196 Mc per added
plane** (mean 191 K sys).

What that increment must contain, by the replay: 280 x 406 (mix) + 200 x (329 + 51) = 189.7 K comp =
151.7 K sys if every line is issued, or 200 x 786 = 125.8 K sys if the planner skipped the 80 border
lines. So **the pool any fetch or sequencing change can touch is 39-65 K sys per added plane per
frame** (141-327 sys a pass): fetch latency + CDC + the CPU's issue gap (+ planner compares if
exposed). With option 8's ~80 sys gap, the first reading leaves ~61 sys = **~75 comp of fetch
latency**, in line with the board's other read figure (a D$ line miss over HP0: ~48 sys,
BENCH_REPORTS). VCAL's row loads cannot resolve it (MIX2 - MIX1 = 386 and 470 sys for one
400-beat row on two boots: scanout contention swamps a ~50-sys latency). Section 5 measures it.

**Not measured, and why:** no board-SoC sim. Its DDR is a model (20-24 clock first beat), so it
would return the model's latency, not the board's; the bench reads the board's own counters.

## 3. Q2: can the layout be done without RTL, and does it change anything?

**Yes, it can.** A cart (or ZigOS) sets plane p's FB_BASE to `B + p * W` and every stride to
`N * W`; FRESCO, video.zig and scene_hash all follow. Stride is a mode cue in three places, so:
normal, scroll and overscan modes are safe (`N * 320` is never 400; overscan's length is fixed);
**fullscreen mode cannot** (its stride IS the row and the scroll wraps on it); medium needs
`stride >= 800` to mean medium-overscan, so a medium plane interleaved at 640+ changes mode; CHISEL's
clip uses D_STRIDE as the width (`blitter.zig clipRect`) and height 200 unless stride is 400.

**It changes nothing by itself.** FRESCO still issues N requests a line from N latched bases, and
the DMA still runs them one at a time with a first beat each. What placement alone can change is
DDR row locality: the N lines become one 1280-byte run instead of rows 64 KB apart. A DDR3 page
miss costs ~tRP + tRCD (~30 ns, ~3 sys) and every fetch is a new request anyway; expected effect
~0, measured by `fr.ilv.pN` (section 5).

**What merging needs in RTL** (option M):
- the plane path computes the group's NEXT plane's line address before its pass (a second
  `row * stride` pipeline: +1 DSP, on the comp geometry path that already needed three stages to
  close 125 MHz) and checks contiguity: same row, same stride, `addr[p+1] == addr[p] + len[p]`,
  no live HSCROLL / scroll mode, same mode; else it falls back to one request a plane (exactness);
- the fetch asks one burst for the run: the buffer holds it (4 x 320 = 160 beats, 4 x 400 = 200,
  of 256: **no BRAM**), but the 256-word request limit and the painter's 8-bit word index grow a
  bit, and each plane paints from its own offset (a per-plane base on `fb_raddr`);
- a held pass whose line is already in the buffer skips FETCH (a "fetched" flag, cleared at a
  non-held pass).
Estimate **+150-250 LUT, +1 DSP, 0 BRAM**; comp timing risk on the geometry path. Baseline
`zm_video_comp` 1,775 LUT; the board build is at 89-94 % LUT with sys WNS ~+0.04-0.07 ns.

## 4. Q3: gain per frame, against the alternatives

L = the board's fetch latency (comp clocks; prior 60, the range 30-120 shown). Only planes of one
line-major group gain: a plane-major stack fetches each plane's line in a different layer pass.

| change | 1 plane | 2 | 3 | 4 (normal) | 4 (overscan) | LUT | ABI |
|---|---:|---:|---:|---:|---:|---|---|
| interleave + merge (M): (N-1) x lines x L | 0 | 0.010 (0.005-0.019) | 0.019 (0.010-0.038) | 0.029 (0.014-0.058) | 0.040 (0.020-0.081) | 150-250 + DSP | carts opt in, layout |
| interleave only, no RTL | 0 | ~0 | ~0 | ~0 (`fr.ilv`) | ~0 | 0 | carts opt in |
| prefetch the group's next plane (P): (N-1) x lines x (L + beats) | 0 | 0.018 | 0.036 | 0.053 | 0.083 | ~150-250 + DSP | none |
| 2-deep CMD / issue gap hidden (Q): (N-1) x 280 x g, g ~80 sys | 0 | 0.022 | 0.045 | 0.067 | 0.067 | ~50-100 | none (firmware) |
| F3 24-bit pictures (studied) | 0.03 | 0.03 | 0.03 | 0.03 | 0.03 | 150-250 | none |
| one plane fewer (cart) | - | 0.19-0.59 | 0.19-0.59 | 0.19-0.59 | 0.19-0.59 | 0 | cart |
| composite at scanout (Fable: no) | all of FRESCO | | | | | 800-1,500 + 4-8 BRAM | LFB double-buffer |

Mc a frame (sys), normal planes 200 fetched lines, overscan 280; budget 1.67 Mc. The carts in or
near the knee that have a group: leonard (3 normal: M saves ~0.02 of the 0.29 it needs; merging
its planes saves ~0.88), union_intro (2 overscan: ~0.013 of 0.46; merging saves ~0.72),
mpp_truecolor's 4 PLANES mode (60 since the copper lists). No cart crosses 60 fps on M.

## 5. The experiment to stage (board only, no RTL, no system change)

Branch `study/plane-interleave`, `fpga/cycles/native/bench/planes.c`: the bench's frame tests now
log, beside each setting's frame cycles, FRESCO's `COMP_BUSY` (`.comp`, comp clocks) and the DMA's
`DMA_BUSY` (`.dma`, sys clocks, the scanout included) over the same window, and add **fr.ilv.p2..p4**:
fr.dirty with planes 0..N-1 line-interleaved at BENCH_VRAM_OFF (stride N x 320; the bases and
strides are put back after, so the results page draws as before). Same passes, same bytes.

Build (done, 61,560 B): `cd fpga && make native-cart NAME=bench ZM_FPU=1` ->
`fpga/build/hcycles/split/native_fpu/bench/{cart.bin,disk.zmd}` (the split card's lean cart, run by
the card's system.rv32; no system or bitstream change). Stage it as the 10-19 runs did (the fat
`zigmachine/demo-bench.zmd` from that disk.zmd + cart.bin, `--fw-dir .../native_fpu`), `killall
glass`, then `fpga/.venv/bin/python fpga/tools/bench_collect.py --load demo-bench.zmd --out <dir>`.
The log grows by 27 lines (12 settings x 3 figures, was 9 x 1; BENCH_MAX_RESULTS 128 -> 160, ~11 of the log's 16 KB).

Read it as (per added plane, i.e. fr.dirty.p(N+1) - fr.dirty.pN, divided by the passes):
- `.comp` increment - (280 x 406 + 200 x 380) = 200 x L (+ 80 x few if the borders are issued):
  **the fetch latency L**; if `.comp` grows by ~158 K instead of ~190 K, the planner skips the borders.
- `.dma` increment - 200 x 41 = 200 x the DDR part of L (grant to last beat); L minus it is CDC.
- frame increment - 0.8 x `.comp` increment = **the sequencer's gap** (issue, waits, planner).
- fr.ilv.pN vs fr.dirty.pN: the layout's own effect (DDR locality); expected within noise.

Decision rule: M is never the pick (P saves more with no ABI). Build **P** only if
(N-1) x 200 x (L + 51) x 0.8 clears ~0.05 Mc on a cart that needs it (L >= ~100 comp at 3 normal
planes); build **Q** if the gap is the bigger part; otherwise neither, and the planes lever stays.

## 6. Q4: what interleaving would cost carts and the browser

- **Contiguous plane assumption.** ZigOS's `clearFrameBuffer` clears `stride x fb_h` with CHISEL
  (with stride N x 320 it wipes the other planes); 6 scene files slice `fb[0..N]`, ~31 index rows
  as `y * 320` / `y * WIDTH`; CHISEL's clip (x1 = D_STRIDE) lets a clipped blit spill into the
  neighbour plane's row. Interleaving would be an opt-in per cart, through a new ZigOS allocator.
- **hw scroll / double buffers break the merge, not the picture.** `setScroll` moves one plane's
  base; HSCROLL scrolls one plane; a cart flipping one plane's base between two buffers leaves the
  run non-contiguous; M must detect each and fall back. Fullscreen-mode planes cannot interleave.
- **vramAlloc** is a bump allocator with no guard; an interleaved block is one allocation of
  N x 64,000 (normal) or N x 112,000 (overscan; 4 = 448 KB of the 1 MiB pool).
- **Browser / scene_hash: no change.** video.zig honours any base and stride, so pictures are
  identical; M would be timing only, with a break test for the fallback (a non-contiguous group
  must not merge: a scroll-mode plane in an interleaved group, pixels compared to vmix).
- **LUT/timing:** section 3.

## Reproduce

`uv run python fpga/tools/video_phase.py tutorial 300 --timing {0,28,100} --line-major --nopfb`
(records under fpga/build/vdump; `make memmap` first in a fresh worktree); bench numbers from
`fpga/bench_results/2026-10-19_bench_w64boot.txt`; the new bench as in section 5.
