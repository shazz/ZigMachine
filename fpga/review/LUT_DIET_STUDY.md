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

### 3.3 Candidates looked at and not taken (why, with the numbers)

| candidate | block | LUT it would touch | why not (or not yet) |
|---|---|---:|---|
| `opt_design -resynth_seq_area` / `-aggressive_remap` / `-resynth_area` | all | -22 / +39 / +34 | §3.1: the build's ExploreArea + control-set merge already take the gain |
| `-control_set_opt_threshold` higher | all | +LUT | converts the 193 byte-lane register enables (fanout 8-10) into LUT logic: more LUT cells, not fewer; the slice wall is LUT sites |
| the copper's checks on both halves of the fetch word (`zm_video_copchk`, 202 LUT) | FRESCO | ~-100 | made on both halves on purpose: the half mux moved after the adders gained -0.77 ns on comp (board_combo7); comp's post-route slack is +0.11 ns, so the saving would re-open timing |
| the blitter's answer flags `got_a/b/c` (195 LUT, 96 FF: a 5->32 decode and a 32:1 read a channel) | CHISEL pixel queue | ~-100 | a per-channel in-order pointer would need the HP read path proven to answer in slot order per channel; the pixel queue is the unit the fast builds failed to place in, and its enables were tuned to -0.53 ns on sys (combo7): not without its own study |
| the pixel queue's slots and the three CDC data queues in block RAM (100 + ~130 LUTRAM) | CHISEL, FRESCO CDC | ~-230 | both read asynchronously (the head's bytes, the compositor's beat the clock they land): a block RAM's synchronous read adds a clock to each and changes the units' throughput; now that the compositor leaves ~10 tiles free (§3.2) the room exists, the proof (blitter tb + mutants, video sim) does not fit one night |
| wide adders into the 8 free DSP48s (`use_dsp`, as `zm_blit_regs.cycles` and the top counters already are) | CHISEL rows (3 x 23-bit `nxt`/`addr`), LINE's `err`, the snoops' `off` | ~-30 a chain, 8 chains | the chains that are not already in DSPs sit on combinational paths into registers that close sys with +0.038 ns (a DSP ALU without its pipeline registers is ~3.5 ns against ~1.5 ns for a 23-bit CARRY4 chain); the accumulators that tolerate the latency (counters) are in DSPs already |
| the glass register block's 16-way 32-bit readback mux (~150 LUT) | ZWINDOW | ~-100 | half the registers read live values (keys level, pointer, cart state/beat, status), so no RAM shadow; the mux already selects on 4 address bits |
| LiteX CSR banks (video 111 LUT, zm_cycles 67, glass, uart) | glue | ~-150 with an 8-bit CSR bus | changes the CSR map: the firmware's csr.h, glass, every board tool. Not "the same register ABI" |
| the stub UART and its CSR bank | glue | ~-1 | measured on `perf/lut-zero-cuts`: 17,606 -> 17,605 |
| the HP register slices' skid halves | glue (3,640 FF) | -- | already cut on 2026-11-01 (`hp_slice always_ready`): what is left is one flop a PS7 pin, the reason the PS7 paths close |
| Gemini's #7/#9: FpuSqrt (139) / FpuDiv (275) trapping to software | ZIGGY FPU | -414 | bit-identical results but not the same speed: the `_f32` carts (raytrace_f32, polkadots_f32) are the FPU's benchmarks; "the FPU stays" |
| Gemini's #2 (PCM channel arrays in flip-flops), #3 (the audio queue's write enables), #5 (BARD without prediction) | CHORUS, BARD | | #2 measured worse (982 -> 1,351), #3 is the misattribution of §2, #5 slows BARD's players (wow_scroller runs at 130 % on a smaller core already, memory `zigmachine-bard-real-load`) |

## 4. What a real diet would take (the options Matt decides)

Nothing in the netlist is dead; the 16,958 cells are the features, the big ones being the blitter's
arithmetic (4.2 k), the cart CPU with its FPU (4.3 k), the compositor (2.8 k), BARD (1.8 k) and the
audio chips (1.7 k). The behaviour-neutral cuts measured tonight are worth tens of LUT, and the fit
stays placer luck. The options that free hundreds to thousands each change something Matt has ruled
out so far, listed with their size so the decision is a number:

| option | frees (est.) | what changes |
|---|---:|---|
| **a 7020** (xc7z020: 53,200 LUT, 140 BRAM, 220 DSP) | everything | the board (Z7-Lite 7020 exists, same footprint); every bitstream rebuilt once; CHISEL v3, the desk mode, prefetch, the hardware dirty bitmap all fit with room |
| the compositor on the sys clock (comp = sys = 100 MHz; `zm_z7.py` already handles `comp_hz == sys_hz`) | ~300-400 LUT, ~500 FF (the three 64 x 16 CDC queues, ReqCross, the bus synchronisers) | the compositor loses 20 % of its clocks a frame: the planes budget (0.59 Mc a plane) and the heavy multi-plane scenes' fps |
| a smaller, slower FPU (iterative multiply/add, same IEEE results) | ~800-1,000 LUT | f32 ops take several clocks instead of one a cycle: the `_f32` carts' fps |
| FPU div/sqrt in software (the trap Gemini proposed) | 414 LUT | same results, slower divides |
| BARD's D$ 16 KB 2-way -> direct-mapped, or 8 KB | ~150-250 LUT | BARD's players' load (some already > 100 %) |
| ZIGGY's D$ 16 KB 2-way -> 1-way | ~150 LUT | the way mux and the second tag compare; roto/voxel carts' hit rate |
| the ARM runs BARD's players (the ARM-side offload) | ~1,800 LUT (ZmSnd) | a new sound path (the glass feeds CHORUS's queue); sample-exactness to re-prove |
| the pixel queue and the CDC queues in block RAM (§3.3) | ~230 LUT | behaviour-neutral in pixels, +1 clock in two units; a proper study with the blitter tb and the video sim |

## 5. The bitstreams

### 5.1 (a) desk + diet + `fast` + `prefetch`: built, closed, on the board

`prototypes/lut_diet/build_board.sh board_diet_pf --ziggy-reads prefetch` (combo16's command line,
`fit_timing`, this tree: desk-border RTL + the RAM repack + study/ziggy-big-reads). Artefacts in
`prototypes/lut_diet/bit_a/` (md5 1296f36f106a75aefd654439be1c60a3).

| | desk build (9 Nov) | (a) diet + prefetch |
|---|---:|---:|
| synth LUT | 16,958 (96.35 %) | 17,014 (96.67 %): +58 the prefetch, -2 the repack |
| placed LUT sites / slices | 15,716 (89.30 %) / 4,400 | 15,739 (89.43 %) / 4,400 |
| FF | 15,953 | 15,978 |
| BRAM tiles | 54.5 (90.8 %) | **44 (73.3 %)** |
| DSP | 72 | 72 |
| control sets | 730 | 747 |
| placer (ExtraTimingOpt) | placed | placed, post-place WNS -0.558 -> phys_opt +0.004 |
| route | -0.041, closed by a re-route | **first route: sys +0.011 / hold +0.018**, comp +0.179, pix +1.178, pix5x +0.582; 0 routing errors, DRC clean |
| CSR map | csr.json | identical (no firmware change) |
| build time (2 threads, quiet box) | | 42 min |

LUT cells did not go down: the behaviour-neutral diet is -8 LUT, +58 for the reads. What changed is
the block-RAM count (-10.5 tiles, -27 RAMB18 in the compositor, each with 36 data pins into the
logic) and with it the routing load around the BRAM columns. Whether that is what let this netlist
place where the 10 Nov `prefetch` builds failed, or a seed, is what §5.2's control build answers.

**On the board** (11 Nov, 01:35; the desk bitstream 58374d06 kept at `KESTREL/rollback/lutdiet_prev/`,
system.rv32 6aa96b5d / glass fd4e886b unchanged, the card's `zigmachine.bit` = 1296f36f, md5 checked
over Wi-Fi before the reboot and over serial after). Everything measured before the swap was measured
again after it, with the same tools (`bench_before/`, `bench_after/`, `fps_before/`, `fps_after/`):

| ZIGGY bench (`bench_collect`, cycles an op) | desk | (a) |
|---|---:|---:|
| `ld.seq.64K` (a word of a sequential read) | 7.23 (55 MB/s) | **3.99 (100 MB/s)** |
| `ld.miss.64K` (a line miss) | 42.2 | **30.7** |
| `ld.chase.miss` | 46.2 | 32.7 |
| `mc.lib.64K` (memcpy, a byte) | 2.51 (40 MB/s) | **1.28 (78 MB/s)** |
| `mc.word.64K` | 2.35 | 1.25 |
| `ic.over.24K` (I$ refills) | 4.67 | 2.95 |
| `cn.ld.alone` / `cn.ld.fill` | 36.2 / 36.4 | 26.6 / 31.6 |
| every store line (`st.*`), D$ hits, CHISEL copies | same to 0.01 c | same |

The study's harness predicted 46.9 -> 87.2 MB/s for a 192 KB read and 38.6 -> 66.1 for a copy; the
board gives 55 -> 100 and 40 -> 78. (`fr.static.p0/p1` read 0 for `comp` in the after-run's first
frames and normal values from p2 on: the frame probe's window moved with the faster memory benches,
and the fps probe below reads the same comp/pass as before.)

| cart (`board_fps`, 12 s) | desk fps / missed | (a) fps / missed | sound, state |
|---|---:|---:|---|
| GEMTEST | 60.2 / 0 | 60.4 / 0 | running |
| union_l16 | 60.4 / 0 | 60.4 / 0 | SNDH level_16, BARD 1/2, running |
| stcs_css3 | 60.2 / 0 | 60.2 / 0 | SNDH thrust, running |
| polkadots | 60.2 / 0 | 60.2 / 0 | running |
| chisel_v2 (QUEUE, AFFINE, MAP, mirror, COLL) | 60.2 / 0 | 60.2 / 0 | running |
| raytrace | 60.2 / 0 | 60.2 / 0 | running |
| polkadots_f32 (FPU) | 34.8 / 124 | 35.2 / 122 | running |
| stniccc (disk stream, MOD) | not measured | 55.9 / 20 | MOD chcknbnk, running |
| notepad (GEM 5, KOS GEMDOS) | not measured | 60.2 / 0 | running |
| demo-gem.zmd | not measured | SystemRefused | the stale GEM disk's table against system.rv32 1.23 (software, not the bitstream) |

No trap, no err, no stall on any cart; the compositor's probe (`comp/pass`, `ready/pass`) reads the
same as before on every cart. **The diet bitstream stays installed.** Rollback, over the serial
console: `mount -o remount,rw /mnt/sd; cp /mnt/sd/KESTREL/rollback/lutdiet_prev/zigmachine.bit
/mnt/sd/zigmachine.bit; sync; reboot`.

### 5.2 (b) CHISEL v2: already in (a)

The brief's "CHISEL v2 never in a bitstream" is stale: the desk build and (a) carry `zm_blit_q`
(QUEUE), `zm_blit_tex` + `zm_blit_tfetch` (AFFINE, MAP), `zm_blit_twalk` (the TRIANGLE edge walk)
and the collision/mirror/fill paths (the hierarchical report of `bit_a/`), HW version 1.17.0 >=
1.11.0 (`gen/memmap.vh`), and `demo-chisel_v2.zmd` runs at 60 fps on both. (b) is (a).
