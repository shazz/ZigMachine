# ZigMachine FPGA SoC review — feat/new-screens-drafts @106ae9c6

> **Lead's note (2026-10-23), read first.** This review was run on the stale branch `feat/new-screens-drafts`
> (547 commits behind main), and on the *default* `--target z7` config, not the board's
> (`--blit --sound-cpu --posted 8` + FPU, 15,040 LUT, sys WNS +0.04 ns). So:
> - **F1 is already done on main** (posted stores, bitstream 3ebb7381: a store 18 -> 2.25 cycles on the board).
> - **F7's bigger I$ is already done** (the board core is I16w2D4: 16 KiB 2-way I$).
> - **F4's margins are the default config's**; the board build's sys margin is the thin one. Lowering comp to
>   100 MHz is rejected: the slow carts (union_main, stcs) are compositor-bound.
> - Kept for the roadmap: **F2** (add a per-frame scanout-underrun counter first; double-buffer only if it fires),
>   **F3** (RGB565 rows: study a form that keeps the planes' alpha — partial alpha and the black tube need it —
>   and measure with the AXI beat counters first), **F5** (fold the blitter's chk/htb/tri paths together with
>   the in-plane overlap fix in chk). Status of everything: `PERFORMANCE_REVIEW.md` (status table).
> - Next run of this chain: point it at main and the board's feature flags.

Scope: the user's four asks — (1) performance: bandwidth, latency, DDR bottleneck, bad design;
(2) resource usage: where LUTs go and what could be saved; (3) headroom for new components;
(4) stabilising the SoC frequency to 100 MHz.

Review baseline: working tree `feat/new-screens-drafts` @ `106ae9c6` ("DMA intros … play their real SNDH
on the sound CPU"), 2026-10-20. `integrate/2026-10-20` already contains later SoC fixes that this tree
does NOT have; where relevant those are called out below (most importantly `e344a37d`, the posted-store
bridge). Every number below is either (a) parsed from a Vivado run whose commands are in
`review/tools/` (evidence under `review/reports/` + `/tmp/opencode/rev/`), (b) a measurement already
recorded in `fpga/CYCLES.md` (the repo's measurement log, cited by log line), or (c) an RTL-structural
derivation whose assumptions are stated and auditable from the named source files.

## Summary

| # | finding (one line) | effort | gain (quant) | risk | impact |
|---|--------------------|--------|--------------|------|--------|
| F1 | HP0 cart-CPU store path is `posted=0`: every store is an AXI round trip → cart needs 2.5–3.8× its SRAM-clock | <1 h (fix already exists in integrate/2026-10-20 `e344a37d`; cherry-pick the bridge part) | removes ~10–14 cycles per store; union_beatdis ceiling 55→61+ MHz-equivalent wall shifts | low (bridge-only change; keep layout change out) | BIG |
| F2 | ZMVideoAXI grants one 400-beat request at a time, non-preemptive (grant order: scanout → write → other reads): a granted compositor row delays the scanout by up to a full row transfer | small (≤50 lines in `zm_video_axi.py`) | bounds scanout jitter; removes underrun headroom risk | low | MAIN |
| F3 | Compositor row I/O is the dominant DDR traffic: ~11.7 MB/frame ≈ 700 MB/s @60 Hz at 3 planes (32 % of DDR3-1066 peak) | med | RGB565 halves the picture share (~4.3 MB/frame) | med | HIGH |
| F4 | SoC clocks: sys=100(+0.405 WNS), comp=125(+0.742), audio@40M, HDMI@200M — four domains, all close | med | all-positive margins today; one-domain SoC still buys F6's CDC simplification | med | MED |
| F5 | zm_blit is the largest custom LUT block after the CPUs: 3,519 LUT + 8 DSP on v5fpu build | med–big | ~500–700 LUT by folding `chk`+`htb`+`tri` sub-paths | high (timing) | MED |
| F6 | CDC LUTRAM queues (comp↔sys) collect in the glue bucket: 436 LUTRAM in `(platform_z7)` all-on, 212 in the default build | small | falls out of F4; boundary between domains gets monitorable | low | LOW |
| F7 | Headroom is config-dependent: default z7 build 44.3 % LUT (55.7 % free), all-on v5fpu 94.1 % | — | default: a new component fits; all-on: needs F5/RAM cuts first | — | informs |
| F8 | YM2149 non-sound features (I/O ports A/B, register readback, /2 divider, A/B/C+sample outputs) are already synthesis-folded away in the replay-only integration | ~0 (nothing to change) | full-ports OOC 272 LUT / 311 FF vs in-SoC 233 LUT / 232 FF: strip-back ≤ 39 LUT + 79 FF ≈ 0.5 % of the SoC; 0 DSP | — | nil |

Effort is rough one-person scale (h = hours). No finding requires a SoC rewrite: F1 is a bridge
config change, F2 an arbiter change; F3 is the only structural item and should be gated on a board probe.

## Method & tooling (reproduce everything)

Three evidence layers; all scripts committed under `review/tools/` (see its `README.md`):

1. **Per-block OOC sweeps** — `ooc_sweep.sh`: Vivado 2026.1 synth → opt → place (`ExtraTimingOpt`)
   → route (`MoreGlobalIterations`) on one RTL block with `clk` forced to 8 ns / 6.67 ns / 10 ns
   (125/150/100 MHz). Per run: `timing_summary.rpt`, `util.rpt`, `hier.rpt`. Isolates block fmax
   from top-level noise. Blocks swept: zm_video_plane, zm_blit_px (+pxq), zm_video_mix (+sdpram),
   zm_audio_soc (+full audio tree), jt49 (default @10 ns; see F8).

2. **Full-SoC postmortem on the current tree** — `synth_full.sh`: regenerate the flat gateware
   (`uv run --with meson --with ninja python -m soc.zigmachine_soc --target z7 --out build/review/soc`),
   then run the repo's own flow-of-record Tcl (`build/board_main/gateware/platform_z7.tcl`, project
   mode, board_main XDC, `ExtraTimingOpt` placement + `AggressiveExplore` route + phys_opt,
   write_bitstream) with ONLY the netlist path retargeted to the regenerated file. Output in
   `/tmp/opencode/rev/pletdir/`: `platform_z7_timing_synth.rpt`, `platform_z7_timing.rpt`
   (-datasheet, 10 paths), `platform_z7_utilization*.rpt` (+ hierarchical), `_route_status`, `_drc`,
   `_power`, checkpoints synth/place/route + `platform_z7.bit`.

3. **Budget extraction** — `hier_budget.py` turns `report_utilization -hierarchical` into ranked
   per-depth tables (the LUT answer). `ooc_collect.py` aggregates the OOC sweeps into one table.

Board anchors are NOT re-derived: they are cited from `fpga/CYCLES.md` with the exact log line.
Run the whole evidence chain yourself:

    cd fpga && bash review/tools/chain.sh      # ~25 min, sequential Vivado (single licence seat)

## Findings (detail)

### F1 — HP0 (cart CPU) store path: posted=0 blocking stores

**Claim.** `soc/zm_hp.py:84` (`posted: int = 0`, docstring line 18: "blocking: no store is
posted, so `drained` needs no store-buffer term"): each store is an AXI single-beat write and the
Wishbone store stalls until the write response returns. CYCLES.md "What the measurements say" §1
(lines ~281–295): with the `hp` (blocking) bridge every cart needs 2.5–3.8× its SRAM clock
(union_beatdis 55→194 MHz, skystrike 115→325); union_beatdis issues ~125 K stores/frame; at
150 MHz a frame has 2.5M cycles → 10 cycles/store eats half the budget.

**Evidence.** `soc/zm_hp.py` (verbatim above), CYCLES.md §1, and the measured variants:
an 8-entry posted-write buffer (`hp_sb`) recovers EXACTLY the `hp_free` floor (buffer never fills
at ≤1 store/few cycles); write-combining (`hp_wc`) adds nothing to cycles, and reads-wait-for-drain
(`hp_wc_rdwait`) costs ~1 MHz. Read latency after the buffer: +6–14 % (§3, 61/112/129/28 vs
55/98/115/26 MHz on one-cycle SRAM); under a saturated DDR (`hp_load_wc`, 410 ns refill) 69/135/152/32.

**Baseline status.** The fix exists on `integrate/2026-10-20` (=commit `e344a37d`: "posted=8
stores, line-major") but `git merge-base --is-ancestor e344a37d HEAD` fails for this tree:
the baseline ships the blocking path. Cherry-pick ONLY the bridge/store-buffer hunk; the
line-major PFB layout change rides a different review item (F3) and should not land together.

| item | effort | gain | risk | impact |
|------|--------|------|------|--------|
| posted=8 buffer in the HP0 bridge | <1 h | per-store cost: ~10–14 cycles → 1 ack cycle | low | BIG |

### F2 — ZMVideoAXI arbiter: one request at a time, no preemption

**Claim.** `soc/zm_video_axi.py` docstring + `_grant()` (lines 70–88): one request (a 400-beat
row) at a time; grant priority when idle is reads[0] (the scanout) → the write port → the
remaining reads (the compositor's). Once a request is GRANTED it runs to completion (`self.active`
held until `d_left==0 & a_left==0 & b_out==0`, line 67–68): the scanout's request cannot preempt
an in-flight compositor row read or write. A compositor pass does two full-row reads (PFB +
picture) and two full-row writes per pass — so the scanout's per-row fetch latency jitter is
bounded by a full row transfer (~3.2 KB), and the pass latency budget inherits that jitter.

**Evidence.** Source contract quoted above (readable in `zm_video_axi.py:1-22, 70-88`), plus the
timing geometry in `rtl/video/zm_video_rowio.v` (LOAD→PAINT→STORE serialization, F3) and
`rtl/video/zm_video_scanfetch.v` (scanout row timing). The instrument of record for the measured
form of this claim is the existing board read-path probe, `soc/zm_hp_probe.py` (first beats of the
last read at both AXI sys side and comp side) — one afternoon to wire per-row stats.

**Fix sketch.** Options, cheapest first:
- **Scanout row double-buffer** (fetch row n+1 while painting row n): removes the deadline
  coupling to the compositor's grants. Structural, ~50 lines in the DMA/scanner + a line buffer.
- Let the arbiter split a granted request mid-row: NOT tiny (response defer per burst), skip.
- Reduce the number of granted requests per pass: see F3 (fill-only passes already exist via
  `cmd_fill`; premises documented in `rtl/video/zm_video_pass.v`).

### F3 — DDR bandwidth: compositor row I/O dominates

**Claim (structural).** Per plane-line pass: read PFB row (400 64-bit beats = 3.2 KB) + read
picture row (400 beats) + write both (2×400 beats) = 1,600 beats = 12.8 KB. 280 lines × 3 planes
= 840 passes/frame → 1,344 k beats = 10.75 MB/frame; scanout fetch = 280×400 beats = 0.9 MB/frame;
BG store +400 beats. Total ≈ **11.7 MB/frame ≈ 702 MB/s at 60 fps** vs DDR3-1066 (×16) peak
2.13 GB/s → ~33 % of the DDR just for video at 3 planes; **40 %+ at 4 planes**. These are the RTL's
own op counts (`zm_video_rowio.v`, `zm_video_dma.py` bursts, `zm_video_pass.v` per-pass phases);
nothing here is a model of DDR timing.

**Evidence.** Files above; DDR window proof in `soc/zm_hp.py` (`ddr_addr`, HP Slaves' 32 MiB /
128-byte windowing). Board check pending (below).

**Options (repo's lean, ranked):**
- **16-bit picture (RGB565)**: halves the picture share of LOAD/STORE (~4.3 MB/frame of the 11.7);
  paint math stays 32-bit internally, only the row hops shrink. Mixer DSPs have headroom
  (5→8-bit expansion is a bit-replication add; see F5 DSP slack: 38/80).
- **Row double-buffering (F2)**: does NOT reduce bytes, only decouples LOAD/STORE from PAINT.
  It is the latency/underrun fix, not the bandwidth fix.
- **Fill-only passes**: already supported (`cmd_fetch=fill`), no work required unless the scenes
  regress.
- The plan-of-record's line-major PFB (post-`e344a37d` layout) changes beat locality, not counts —
  re-verify burst counts after it lands (AR/AW counters in `zm_video_dma.py` make this a cheap
  board experiment).

### F4 — SoC frequency stabilization to 100 MHz (the user's ask)

**Claim.** The SoC's clock family (fresh flow-of-record build of the current tree,
`/tmp/opencode/rev/pletdir/timing_route.rpt`) is:

| domain | design | post-route WNS | margin |
|--------|--------|----------------|--------|
| PL_CLK_50M | 50 MHz pad in (no critical paths) | — | — |
| make_z7_clkout0 | sys = 100 MHz | **+0.405 ns** (TNS 0.000, WHS +0.033) | 4.1 % (tightest) |
| make_z7_clkout1 | comp = 125 MHz | +0.742 ns | 9.3 % |
| make_z7_clkout2 | pix = 40 MHz (PIX_CLK) | +13.616 ns | huge |
| make_z7_clkout3 | pix5x = 200 MHz (5× TMDS serializer) | +0.756 ns | 15 % |

All four MMCM domains close POSITIVE through the repo's own flow (`ExtraTimingOpt` place +
`AggressiveExplore` route + phys_opt, board_main XDC), route fully clean (15,666/15,666 nets),
DRC clean, bitstream written. The OOC sweeps price the same blocks without SoC noise
(`review/reports/ooc_summary.md`): plane 158/162 MHz, blit_px 126/159 MHz (125/150 targets),
mix 140 MHz @125 target, audio_soc 104 MHz @100 target. Meaning: **comp@125 and sys@100 both
hold today**; the 4 % sys margin is the frequency WATCH-item for adding new components, not a
closure risk. Stabilising "one SoC frequency" therefore costs nothing on timing and buys the
F6 CDC simplification — but comp@100 mildly shrinks the compositor's cycle budget (F3): do it
TOGETHER with the F2 scanout double-buffer so underruns cannot follow.

### F5 — Resource: where the LUTs go, and headroom

Board_v5fpu (largest config: FPU + sound CPU + blitter): **16,563 LUT (94.1 %)**, 17,083 FF
(48.5 %), 13 RAMB36 + 63 RAMB18 (44.5 RAMB36E ≈ 74 %), 38 DSP (47.5 %). Ranked per-depth tables:
`review/reports/board_v5fpu_budget.md` (from the build's
`platform_z7_utilization_hierarchical_synth.rpt`).

The fresh flow-of-record build of the CURRENT tree changes the bracket: the default `--target z7`
SoC (this branch, 2026-10-20) is **7,797 LUT (44.3 %), 8,290 FF (23.6 %), 32.5 RAMB36E (54.2 %),
24 DSP (30 %)**, fully routed (`route_status`: 15,666/15,666 nets, 0 errors), with DRC clean and
the bitstream written (`review/reports/soc_plet_budget.md`, from `/tmp/opencode/rev/pletdir/`).
Why the spread: the z7 target's SoC features are opt-in (`soc/zigmachine_soc.py:189-193` —
`--blit` puts the blitter on HP2, `--sound-cpu` puts the players on the sound CPU sharing HP3);
the default plet build instantiates ONE small `VexRiscv` (~2.1 k LUT incl. 4 KiB I$/D$) and none
of the two. So the honest headroom answer is per-config:

| config (SoC feature flags)                   | LUT   | %LUT | RAMB36E % | DSP % | routed/drc           |
|----------------------------------------------|-------|------|-----------|-------|----------------------|
| default `--target z7` (current tree)         | 7,797 | 44.3 | 54.2      | 30.0  | 15,666/15,666, clean |
| board_main (Oct 10; +I16/D4 core, blitter)   | 11,803| 67.1 | —         | —     | (recorded)           |
| board_v5fpu (all-on: FPU+sound CPU+blitter)  | 16,563| 94.1 | 74.2      | 47.5  |                      |

Level-1 ranking of the DEFAULT current-tree build (LUT, % of SoC):

| block | LUT | %SoC | notes |
|-------|-----|------|-------|
| VexRiscv (cart CPU, small core) | 2,082 | 26.7 % | 4 KiB I$ 606 LUT + D$ dataCache 446 |
| zm_video_out (scan+comp)        | 1,835 | 23.5 % | u_comp 1,639 + 30 RAMB18 + 13 DSP |
| zm_audio_soc                    | 1,816 | 23.3 % | u_pcm 260 LUTRAM + 276 LUTRAM in glue |
| (platform_z7) glue + PS         | 896   | 11.5 % | 212 LUTRAM — CSR/interconnect glue |
| zm_hdmi_out                     | 612   | 7.8 % | |
| zm_glass_regs + osd             | 556   | 7.1 % | |

**The all-on config (v5fpu) level-1 blocks, for contrast** (full ranked table in
`review/reports/board_v5fpu_budget.md`):

| block | LUT | %SoC | notes |
|-------|-----|------|-------|
| VexRiscv (cart CPU, I16w2D4Seal) | 4,223 | 25.5 % | 4 KiB direct-mapped I$ `IBusCachedPlugin_cache` |
| zm_blit (blitter)              | 3,519 | 21.2 % | core 2,358 + regs 1,241; 8 DSP |
| ZmSnd_VexRiscv (sound CPU)     | 2,089 | 12.6 % | same core family, smaller config |
| (platform_z7) glue + PS        | 1,919 | 11.6 % | 436 LUTRAM in CSR/interconnect glue |
| zm_video_out (scan+comp)       | 1,839 | 11.1 % | u_comp = 1,645 LUT + 30 RAMB18 + 13 DSP |
| zm_audio_soc                   | 1,795 | 10.8 % | u_pcm = 773 LUT + 260 LUTRAM |
| zm_hdmi_out                    | 622   | 3.8 % | |
| zm_glass_regs + osd            | 558   | 3.4 % | |

**Correction to the old review** (`review.old.7z` PERFORMANCE_REVIEW.md): its "14,888 LUT" is not
any build in the repo; the real bracket is **board_main 11,803 @67 %** (no FPU/sound-CPU; Oct 10
build) ↔ **board_v5fpu 16,563 @94.1 %** (the full config). Its "258 LUT per HP slice" is the cost
of ONE bridge measured in isolation, not "four HP ports cost 1 k".

### F6 — CDC LUTRAM queues and 125 MHz pairing

**Claim.** comp↔sys crossings ride LoggingModule-generated CDC queues realized as LUTRAM;
in the hier budgets they land in the `(platform_z7)` glue bucket (436 LUTRAM all-on v5fpu,
212 LUTRAM in the default plet) and in `u_comp`'s RAMB18 columns. With comp@125 and sys@100
(F4) the queues also buffer the scanout's crossing debit committing to fixed row deadlines;
F2's jitter fills them. Stabilising comp=100 (F4) reduces this; 16-bit pictures (F3) halve row
bytes → the PFB hop drops 400 → 200 beats, and the queues halve their row reserve too.

### F7 — Headroom and cheapest savings (informed by F5)

- **Caches are the cheap room insurance**: cart-CPU I$ 4 KiB direct-mapped → 16 KiB 2-way costs
  ~47 LUT + 3.5 RAMB36E (CYCLES.md's budget line) and is a BRAM swap we can afford (74 % → 84 %
  if doubled for the sound CPU too, still below ceiling).
- **On the DEFAULT config (the plet) there is nothing to cut yet**: 44.3 % LUT / 54.2 % RAMB36E /
  30 % DSP is enough free room for a new component outright; the honest squeeze only starts once
  `--blit --sound-cpu` (+FPU) are in (v5fpu 94.1 %) — there the foldable blitter sub-paths
  (`chk` 522 + `htb` 68 + `tri` 108 LUT) and RGB565 (below) are the levers.
- **RGB565 (F3)** frees ~16 RAMB36E (30 RAMB18 in u_comp → ~half) AND halves glue/CDC queue
  pressure — the swap that pays for a new component twice.

**Top-3 one-day path:** F1 (cherry-pick) + F2 (scanout double-buffer) + F4 (comp clock → 100 MHz)
land inside one work day; F3 (RGB565) is structural and gated on the board probe.

### F8 — YM2149 non-sound features: nothing to reclaim (measured)

Question (raised in review): the YM2149 carries non-audio features — the two I/O ports (registers
R14/R15 driven to the pads), register readback via `dout`, the `sel=0` clock-divide-by-2 mode, and
the per-channel outputs A/B/C + `sample`. Stripping them — would it give back silicon?

- **They are already dead in this SoC.** `rtl/audio/zm_audio_ym.v:30` instantiates jt49
  replay-only: `.dout()` unconnected, `.A() .B() .C() .sample()` unconnected, `.IOA_in/.IOB_in`
  tied `8'd0`, `.sel(1'b1)`. The PSG sees only register writes and the summed `sound` bus. The
  "ports" are literally two assigns inside jt49 (`IOA_out = regarray[14]`, `IOB_out = regarray[15]`,
  `third_party/jt49/hdl/jt49.v:66-67`); with the inputs tied off and outputs open, synthesis folds
  the surrounding logic away.
- **Measured bound** (`review/reports/ooc/jt49_10ns` — jt49 with ALL ports live, versus the
  flow-of-record hier rows): OOC full = **272 LUT / 311 FF / 1 RAMB18 / 0 DSP / fmax 172.5 MHz**;
  in-SoC (folded, plet hier) = **233 LUT / 232 FF / 1 RAMB18 / 0 DSP**. The entire possible prize
  of stripping is ≤ **39 LUT + 79 FF ≈ 0.5 % of the default SoC** (0.2 % of v5fpu) — and the
  RAMB18 (18-kbit block, the log/antilog look-up in `jt49_exp`) survives in both, i.e. it is a
  sound-path table, not a strip candidate.
- **No DSP in jt49.** An early draft of this review read the `u_psg` hier row's "1" as a DSP; the
  column is RAMB18. None of jt49's six RTL files infers a multiplier; its OOC run confirms 0 DSP.
- **Context for where audio LUTs actually live** (default build): u_pcm (Paula) 768 LUT + 3 DSP,
  jt49 233, u_mix 112 + 2 DSP, POKEY u_pokey 326. The only genuine "strip" candidate in audio is
  dropping the POKEY block (needed only for tunes that target it) — which is a feature decision
  about a second sound chip, not a YM cleanup.
- **Verdict:** leave jt49 as-is. Even fully loaded it is timing-trivial at the audio clock
  (40 MHz used vs 172 MHz fmax) and costs 3 % of the default SoC's LUTs; the strip-back rate above
  is an order of magnitude below change-noise.

## Next steps (concrete, ordered)

1. Merge the posted-store bridge change from `e344a37d` into this branch (without the layout
   change). CYCLES.md's numbers move the cart MHz ceiling immediately.
2. Board probe: wire `soc/zm_hp_probe.py` (or the AXI AR/AW counters in `zm_video_dma.py`) to
   log one 3-plane frame; verify F3's ~11.7 MB/frame against actual AXI beats. One afternoon.
3. Decide RGB565 vs row double-buffering with the probe in hand; land F2's chosen fix together
   with any comp-clock drop to 100 MHz (F4/F6 interplay).

## Notes for the record

- `review.old.7z` PERFORMANCE_REVIEW.md is background only: the "14,888 LUT" figure is dead (see
  F5 correction), the per-HP-bridge number is per-isolated-bridge, and its DDR bandwidth section
  uses the same structural beat-math as F3 but never shows the count.
- Vivado: node-locked, valid until 09-oct-2027, single-seat → chain runs OOC sweeps sequentially.
- Host: 4 cores / 16 GB; an OOC sweep ≈ 1.5–2 min; a full-SoC flow-of-record run ≈ 5 min from
  a clean tree (LiteX regen included). Static power estimate on the default build: 0.553 W total
  on-chip (`review/reports/plet/platform_z7_power.rpt`).
- Raw evidence is committed under `review/reports/ooc/` (per sweep: `timing_summary.rpt`,
  `util.rpt`, `run.tcl`) and `review/reports/plet/` (the SoC flow-of-record reports). The
  checkpoints (`*.dcp`, 10–30 MB each) and the raw `/tmp/opencode/rev/` trees are reproducible
  via the committed chain scripts and were left out of git.

