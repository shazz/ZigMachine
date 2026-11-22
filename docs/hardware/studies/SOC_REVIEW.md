# ZigMachine FPGA SoC review (opencode, 2026-10-22; edited 2026-10-23)

Scope asked: (1) performance: bandwidth, latency, DDR bottleneck, bad design; (2) resource usage: where LUTs
go and what could be saved; (3) headroom for new components; (4) a stable 100 MHz SoC.

**Read this first.** The review was run on a stale branch (`feat/new-screens-drafts` @106ae9c6, 547 commits
behind main) and on the *default* `--target z7` config, not the board's (`--blit --sound-cpu --posted 8` +
FPU: 15,040 LUT, sys WNS +0.04 ns on main). The lead removed what main had already superseded:
- posted stores on HP0 (old F1): **done on main** (bitstream 3ebb7381, a store 18 -> 2.25 cycles on the board);
- the 16 KiB 2-way I$ (old F7): **done on main** (I16w2D4 core);
- the default-config timing table and "drop comp to 100 MHz" (old F4): **not applicable** (the board config
  is the tight one, and the slow carts are compositor-bound, so a slower comp clock would hurt them).
What is left below still applies to main. The status of every SoC item lives in `PERFORMANCE_REVIEW.md`.

## Summary (still relevant)

| # | finding | effort | gain | risk | next step |
|---|---------|--------|------|------|-----------|
| F2 | The video AXI arbiter grants one 400-beat row at a time, non-preemptive: the scanout fetch can wait a whole compositor row | small | removes underrun risk | low | per-frame scanout-underrun counter on the board; scanout row double-buffer only if it fires |
| F3 | Compositor row I/O dominates DDR traffic (~11.7 MB/frame at 3 planes, structural count on the old tree) | med | 16-bit rows halve it, free ~16 BRAM | med (alpha) | count the real AXI beats on main; then RGB565 + alpha |
| F5 | The blitter is the largest custom block (3,519 LUT + 8 DSP, v5fpu build) | med-big | ~500-700 LUT by folding `chk` + `htb` + `tri` | high (timing) | do it with the in-plane overlap fix in `chk` |
| F6 | comp<->sys CDC queues are LUTRAM in the glue bucket | small | modest | low | falls out of F3 (half the row bytes) |
| F8 | jt49's unused ports are already folded away | none | <= 39 LUT | none | leave it |

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
- Line-major compositing (now on main) changes how many passes a frame takes for handler-free
  planes, so re-derive the counts on main (AR/AW counters in `zm_video_dma.py`: a cheap board
  experiment).

**Caveat (lead, 2026-10-23).** The PFB/picture rows carry ALPHA: partially transparent palette entries
(ancool's stars, the music scene) and the black tube (an alpha-0 pixel shows the tube) depend on it. A plain
RGB565 row drops it. Candidates: RGB565 + a 1-bit (or 2-bit) alpha plane, or RGBA5551/4444 where the palettes
allow; check the machine's palettes first (ST colours are 3-4 bits a channel, so RGB565 itself is lossless
for them). Measure the real AXI beats on the board before building anything; line-major + W64 (main) already
cut the per-frame compositor cost (4 planes 3.42 -> 1.00 Mc), so re-derive the byte count on main.

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

### F6 — CDC LUTRAM queues and 125 MHz pairing

**Claim.** comp↔sys crossings ride LoggingModule-generated CDC queues realized as LUTRAM;
in the hier budgets they land in the `(platform_z7)` glue bucket (436 LUTRAM all-on v5fpu,
212 LUTRAM in the default plet) and in `u_comp`'s RAMB18 columns. With comp@125 and sys@100
the queues also buffer the scanout's crossing debit committing to fixed row deadlines;
F2's jitter fills them. 16-bit pictures (F3) halve row
bytes → the PFB hop drops 400 → 200 beats, and the queues halve their row reserve too.

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

## Next steps (ordered, on main)

1. Point this chain at main with the board's feature flags (`--blit --sound-cpu --posted 8`, FPU) so the
   LUT and slack tables describe the shipped SoC.
2. Board probe: a per-frame scanout-underrun counter (F2) and the AXI AR/AW beat counters in `zm_video_dma.py`
   for one 3-plane frame (F3).
3. With the probe in hand: decide RGB565 + alpha (F3) and whether the scanout needs a double buffer (F2).
4. Fold the blitter's `chk`/`htb`/`tri` paths together with the in-plane overlap fix (F5).

## Notes for the record

- Vivado 2026.1, node-locked, single seat: the chain runs its OOC sweeps one after another.
- Raw evidence is under `review/reports/` (per-sweep `timing_summary.rpt`, `util.rpt`, `run.tcl`, and the
  flow-of-record reports); checkpoints (`*.dcp`) and `/tmp/opencode/rev/` are reproducible from
  `review/tools/` and were left out of git. Those reports describe the OLD tree's default config.
