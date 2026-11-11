# LUT diet of the 7010: where the LUTs go, and what a diet that keeps every feature can free

Study, 10-11 Nov 2026, branch `study/lut-diet` (on `feat/desk-border-colour` bbaf4eb3 + `study/ziggy-big-reads`
acfac8cf). Matt: "find miracles". Every number below has its report under prototypes/lut_diet/
(the desk build's own reports in `desk_ref/`, the cell dump and its bills in `probe/`, the OOC runs in `ooc/`).

## 1. The reference: the desk-border build (9 Nov, combo16 command line, fit_timing)

| stage | LUT (sites) | FF | slices | BRAM tiles | DSP | control sets |
|---|---:|---:|---:|---:|---:|---:|
| after synth (cells, before LUT pairing) | 16,958 (96.35 %) | 15,884 | | 54.5 / 60 | 72 / 80 | |
| after opt (ExploreArea + control-set merge) | 16,745 | 15,812 | | | | 723 |
| placed + routed (LUT6_2 pairs count once) | **15,716 (89.30 %)** | 15,953 | **4,400 / 4,400** | 54.5 (90.8 %) | 72 (90 %) | 730 |

It closed timing only by a re-route (NoTimingRelaxation + phys_opt AggressiveExplore): sys +0.038 ns.
The `fast` (16,880 at synth) and `prefetch` (16,999) builds **failed in the placer**: not for want of LUT
sites but in "Post Placement Timing Optimization" (phase 4.1.1.2 of `place_design -directive
ExtraTimingOpt`): the placer's own replication could not commit four flip-flops
(`u_pcm/s_reg[3,5,6]`, `pxu/i_a_reg[21]`, `board_reads_fast_nto/gateware/vivado.log`). The retry that
did place (directive Explore) routed at WNS -3.35 ns with 83 % of the path in routing: congestion. So the
wall is the *density* at 89-90 % of the LUT sites (packing and routing), and a build is placer luck
within about +-100 LUT of the desk build.

**The 1,712 wasted LUT sites.** The routed report's "LUT in front of the register is unused: 1,712":
of the 1,884 LUT sites the design leaves empty, 1,712 sit in slices whose flip-flops the placer could not
pair with a LUT (a control set the slice's LUTs' own flops do not share). That is why slices read 100 %
at 89 % LUTs: the LUT count is the lever, and so is the number of standalone flip-flops near the PS7
(the top glue: 3,640 FF for 842 LUT cells).

## 2. Where the LUTs go (synthesis cells of the desk build, `probe/cells_synth.txt`, bills by `probe/group.py`)

LUT = LUT cells before pairing (so the columns add up to 19,000-odd, not 16,958); the hierarchical
report's "Total LUTs" of the same blocks is in brackets.

| block | LUT cells (hier. LUTs) | FF | CARRY4 | LUTRAM | DSP | BRAM | what it is |
|---|---:|---:|---:|---:|---:|---:|---|
| zm_blit (CHISEL v2, edge walk) | 5,023 (4,232) | 2,883 | 557 | 308 + 33 RAM32M | 24 | 1 RAMB18 | the box checks, the row pipelines (3 x zm_blit_row), LINE, TRIANGLE, AFFINE/MAP, the pixel unit + its queue, the QUEUE sequencer |
| VexRiscv (ZIGGY, I16w2D16w2SealFpuZmxE) | 5,008 (4,295) | 3,194 | 245 | 20 | 6 | 4 RAMB36 + 17 RAMB18 | FpuCore 1,828 (div 275, sqrt 139), I$ 615, D$ 390, the rest the pipeline + MUL/DIV + seal |
| zm_video_out (FRESCO) | 3,051 (2,769) | 2,535 | 245 | 264 + 33 RAM32M | 17 | 2 RAMB36 + 31 RAMB18 | copper 687 (its checks 202), planepath 444, regs 327, bg 185, mix 168, pass 145, rowio 135 |
| ZmSnd_VexRiscv (BARD, SndNdD16Dyn8Sx) | 1,955 (1,766) | 1,203 | 71 | 0 | 4 | 5 RAMB36 + 14 RAMB18 | I$ 465, D$ 419, the pipeline 880 |
| zm_audio_soc (CHORUS) | 1,815 (1,749) | 1,111 | 159 | 344 + 17 RAM32M | 8 | 9 RAMB18 | pcm 651 (212 LUTRAM: the 4 channels' state), pokey 274, sched 236, ym (jt49) 228, mix 111 |
| (top) LiteX glue | 842 (974) | 3,640 | 48 | 496 + 61 RAM32M | 13 | 6 RAMB36 | the two WishboneHP bridges (line buffers 2 x 256 FF), the HP register slices (8 x 66 FF), the video CDC (159 FF), the CSR banks (video 111, zm_cycles 67 LUT), the snoops |
| zm_hdmi_out | 689 (535) | 768 | 19 | 0 | 0 | 1 RAMB18 | the TMDS + audio island transmitter |
| zm_glass_regs + osd + ptr (ZWINDOW) | 609 (551) | 550 | 19 | 52 | 0 | 2 RAMB18 | the ARM's register block (a 16-way 32-bit readback mux), the OSD, the pointer |

The 13 top-level DSPs are the six zm_cycles counters, three sound-register counters, the video busy/frame
counters and the two volume multipliers (`(* use_dsp *)` accumulators, on purpose: a 32-bit counter in a
DSP costs no slices).

**The hierarchical report misleads on two rows, and the RTL does not.** `zm_blit/regs` reads 1,062 LUT
in it: the register block's RTL (byte-lane flops, two LUTRAM taps, one DSP counter) cannot cost that. The
cell dump shows the 1,002 "logic LUTs" are the core's arithmetic that *consumes* `rf` (the box checks
`bx1`/`by1`/`s_hi`, LINE's `dx`/`dy`, the products' operands), which Vivado's rebuilt hierarchy files
under the instance that drives their inputs. The same for the three `zm_video_sdpram` wrappers charged
128 + 127 + 66 LUT with 0 FF: those are the copper's half-select mux and its checks (`blk_ok_i_*`,
`h2[*]`), not RAM glue (Gemini's proposal #3 and the roadmap's open "u_q 134 LUT" question: closed, the
wrapper is free). Nothing in the design is dead or debug-only: `zm_video_copchk` and `zm_blit_chk` are
the copper's and the blitter's run-time range checks (ABI), the CSR banks are 36 registers, the UART is a
depth-2 stub.

## 3. Candidates measured

Measured in Vivado out of context, placed and routed (`prototypes/lut_diet/ooc_video_out.sh`: 8 ns clk,
25 ns pix, the recipe of decisions.md 2026-11-08), or on the desk build's own checkpoints.

### 3.1 Implementation knobs (no RTL change) — nothing

From the desk synth checkpoint (`probe/opt_variants.tcl`):

| pass | LUT cells | FF |
|---|---:|---:|
| synth (AreaOptimized_high) | 16,958 | 15,884 |
| + opt ExploreArea (the build's) | 16,856 | 15,861 |
| + control_set_merge, merge_equivalent_drivers (the build's) | 16,745 | 15,812 |
| + `opt_design -resynth_seq_area` | 16,723 | 15,776 |
| + `-aggressive_remap` | 16,762 (worse) | |
| + `-resynth_area` | 16,757 (worse) | |

The build already takes every area pass that pays; the strongest extra pass is -22 LUT. The control
sets stand at 723 after the merge (the placer added 7). Not a lever.

### 3.2 The compositor's RAMs in the fewest block RAMs (kept) — BRAM 17.5 -> 7 tiles, LUT -8

`rtl/video/zm_video_sdpram.v` built every buffer as one 8-bit block RAM per byte lane: a shape chosen
on 2026-10-04 because openXC7's bitstreams lost data in wider shapes. Vivado has been the board toolchain
since 10-09. A 256 x 64 buffer in eight RAMB18 uses 2 Kbit of each 18 Kbit; the palette's 1,024 x 32 took
four, the 64-word beam table four (512 bits each). The wrapper now builds ONE array with byte write
enables (the byte-lane shape stays behind `ZM_SDPRAM_LANES`, which `soc/openxc7.py` defines for Yosys),
and Vivado packs it: zm_video_out OOC **BRAM 17.5 -> 7 tiles (31 RAMB18 + 2 RAMB36 -> 4 RAMB18 + 5
RAMB36), LUT 2,809 -> 2,801, FF 2,615 -> 2,600, WNS +0.534 -> +0.630 ns, WHS +0.040 -> +0.051**. The
audio scheduler's queue (`zm_audio_sched u_q`, 2,048 x 64) keeps its 8 RAMB18: a 2,048 x 8 lane already
fills one. On the SoC that is about 10 tiles of the 60 freed (54.5 -> ~44) and 27 fewer RAMB18s, each
with 36 data pins, in the compositor's routing. Behaviour: the same RTL semantics (a registered read,
byte enables); proof: the video, mix, desk, tube, line-major and audio testbenches below.
