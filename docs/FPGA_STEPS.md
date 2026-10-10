# ZigMachine on an FPGA: progress log

What has been done toward [`ZIGMACHINE_IN_FPGA.md`](ZIGMACHINE_IN_FPGA.md),
what each step measured, and what is next. The working tree is [`fpga/`](../fpga/README.md).
Newest status first. Every number here was measured, not estimated, unless it
says otherwise.

## Status at a glance

| Plan step | What | State | Result |
|---|---|---|---|
| — | Architecture decision (RISC-V, not a wasm softcore) | **done** | ADR 2026-10-01 in `decisions.md` |
| — | `fpga/` tooling: cores, uv env, memmap export, cost tool | **done** | `make -C fpga setup && make -C fpga check` |
| 0a | Every cart through wasm2c, then compiled for `rv32imf` | **done** | **90 / 90** compile, no cart changes |
| 0b-i | Native C host: machine + ROM + cart, all wasm2c'd | **done** | **98 / 98 fingerprints identical** to `scene_hash.mjs` |
| 0b-iii | Memory path: DDR via HP, store buffer, caches | **done** | 8-entry store buffer + 16 KiB 2-way I$: **150 MHz holds on DDR** (`784cb2c`) |
| 0b-ii | Cycles per frame on a real VexRiscv (Verilator) | **done** | hashes identical on 9 carts; **150 MHz, no FPU** (`fpga/CYCLES.md`) |
| — | Board files (XDC, schematic, PS7 bring-up) | **done** | `fpga/tools/fetch_board.sh`, gitignored; HDMI pins re-derived from the schematic |
| — | Whole SoC elaborated against the real board | **done** | 2,408 LUTs (13.7 %) synthesised |
| — | Video to the wire: mixer, scanout, TMDS/DVI, in the SoC | **done** | mixer = Chrome byte for byte; 40/40 frames; 90/90 carts replay identically |
| — | openXC7 toolchain (Docker, pinned) + first bitstream | **done** | `make -C fpga blink`; the full SoC routes |
| — | f32 FPU variant of the cart CPU (`vexgen ... fpu`, RV32F, no D) | **measured, not adopted** | +2,348 LUT / +1,900 FF / +2 DSP (13 % of the 7010); hashes 16/16 equal; no clock-setting cart gains a cycle, the f64 carts get 5-6 % slower; fmax: **does not place** under openXC7 (base 91.7 MHz); see `fpga/CYCLES.md` "f32 FPU" |
| — | Timing closure under openXC7 (pass 2) | **done at 100 MHz** | glass SoC **meets sys 100 / comp 125 MHz** (seed 8, pinned); compositor on its own clock; skystrike needs 119 |
| — | The glass: ARM loader + OSD menu + USB keyboard/mouse/pads ([`FPGA_GLASS.md`](FPGA_GLASS.md)) | **built, host-tested** | GP0 regs + OSD in RTL (19/19 break tests), Zig `glass` (37 tests), input break tests 18/18, 9 board images land byte for byte; **GP0 + OSD proven on the board from U-Boot** |
| 1–7 | **Board bring-up on the real Z7-Lite** | **7 milestones on silicon** | blink · HDMI video · U-Boot + DDR · HDMI audio · ARM→GP0→OSD · YM music · **the first cart at 60 fps from DDR** (picture fix pending on the board: see "the picture bug hunt") |
| RTL | Video timing (`zm_vtiming`) | **done** | 64 LUTs, CXXRTL-tested over 2 frames |
| RTL | Video compositor: planes, palettes, border, BEAM, all modes | **done** | **32/32 frames pixel-identical** to the machine; 25/25 mutants caught; 1,169 LUTs |
| — | DDR framebuffer video: sequencer, snoop, double buffer, scanout DMA | **done** | the cart CPU + the RTL video in Verilator: **5/5 carts hash = scene_hash** (tutorial, union_main, badflicker, equinox, dhs_0pxl0reg); 49/49 RTL mutants caught |
| — | **Sound on the board SoC**: the audio core behind a stamped write queue, HDMI with audio, the players (SNDH = Musashi) in software on the cart CPU (ADR 2026-10-09) | **sim done, on the board, to be heard** | the core applies the machine's writes at the machine's samples: **1,261 / 1,261 writes** (sos.sndh, 94,080 samples) and the core's output = the core fed the machine's writes, **148,010 / 148,010 samples bit for bit**; MOD within 25 LSB (off-grid gains); a dropped YM write and a PCM address one byte off are caught; Vivado **sys 100 MHz met** (WNS +0.139 ns); easy SNDH **0.28 Mc a frame (17 %)**, a 7.6 kHz digidrum **2.95 Mc (177 %)**, a 15.7 kHz one **7.95 Mc (477 %)** at 100 MHz |
| — | The blitter on the board SoC: `zm_blit` on **HP2**, registers tapped off the CPU's stores, the start from the firmware's `hwBlit` (ADR 2026-10-04; z7 `--blit`) | **sim done** | `make hp-sim` (`ZM_BLIT=hw`): **blitter (10 frames) and tsl_hybridglenz (10, and 120) hash = scene_hash**; a dropped register store and a DDR base one beat off are caught; hwBlit **26 K cycles vs 386 K** a call (blitter, 15x), **116 K vs 4.6 M** (tsl, 39x); tsl frame 2.3 Mc vs 29.1 Mc; +2,646 LUT, +1,578 FF, +8 DSP |

---

## 2026-10-09: sound on the board SoC

The board SoC plays the machine's music: the audio core (`fpga/rtl/audio/`) is in the
SoC, the picture leaves through HDMI with 44.1 kHz audio instead of DVI, and the
players (MOD, YM dump, SNDH = the tune's 68000 code on Musashi) run in software on
the cart CPU (ADR 2026-10-09 "SNDH in software on the cart CPU"; an audio CPU later).
Design and numbers: [`FPGA_AUDIO.md`](FPGA_AUDIO.md) section 6.

- **The register path.** `demo-audio.wasm` through wasm2c in the firmware, its own
  3 MiB memory in DDR; each chip call becomes the core's register writes, stamped
  with the sample it lands before in the machine's stream; the firmware pushes them to
  `AUDIO_WINDOW` (0x9200_0000, M-only: outside every seal window) and
  `rtl/audio/zm_audio_sched.v` (2,048 entries) applies each at its sample, between
  two mixes. The firmware renders 67 ms ahead of the sound.
- **PCM** is read where the machine keeps it, in the players' memory in DDR, one
  byte at a time on **HP3** (`soc/zm_audio_soc.py AudioHP`).
- **Proof in sim** (`tools/audio_sim_run.py`: the board SoC in Verilator, a tap on the
  core, against `host_audio`, the native host with the machine's own chips):
  - tutorial (sos.sndh), 120 frames: **1,261 of 1,261 writes** land in the core at the
    machine's sample counted from the song's start, same value, same order;
  - the core's output equals the core on its own fed the machine's writes on the same
    timeline (`tools/audio_core_replay.py`): **148,010 of 148,010 samples, bit for bit**;
  - tsl_hybridglenz (a MOD), 40 frames: 87 / 87 writes; samples within **25 LSB**
    (the MOD player's gains, v / 64 / 1.4 and pan +-0.6, are off the register grid
    VOL / 256, PAN / 128 and get rounded; on the grid the PCM is exact: the
    `soc_stamped_exact` bench, 13,466 samples);
  - break tests: a YM R8 write dropped in the window (`--audio-break drop`): 1,228
    write differences; the PCM base one byte off (`--audio-break base`): 21,675 samples
    off (worst 3,436 LSB); `sched_early`, `sched_in_mix`, `sched_drop` mutants of the
    queue fail `soc_stamped_exact`.
- **Against the machine's sound**, the YM is jt49 vs ym.zig (section 3): on sos.sndh
  the envelope passages differ, and jt49's result depends on how long it has run
  since reset (replays with different reset-to-song gaps start the shape-10 envelope
  at opposite ends). Spectral similarity 0.935 median, partials 68 %: **listen for the
  bass envelope** on the board.
- **The cost on the cart CPU** (board core, DDR model, sys 100 MHz; budget 1.67 Mc a
  frame at 60 fps): sos.sndh (50 Hz, no timer) **0.28 Mc a frame** avg, 0.42 p95 (one PLAY ~315 kc;
  in the tutorial cart 364 kc avg, 588 kc p95, beside the cart's 466 kc); a MOD 8 kc
  (Paula is RTL); **wow_scroller.sndh (timer A 7.6 kHz digidrum) 2.95 Mc, beat_dis.sndh
  (15.7 kHz) 7.95 Mc a frame**: a digidrum SNDH does not fit the cart CPU at 100 MHz:
  that is the audio CPU's job. A song load is a one-off 21-30 Mc (the 1 MiB of 68000
  RAM zeroed, the image depacked): the stamp re-anchors after it, so the tune starts on
  time. On the board, tutorial runs **45.3 fps without music, 35.7 with**.
- **A firmware bug found on the way**: `cycles/trap.S` never wrote the frame's x0 slot,
  so an emulated misaligned `sw zero` / `sh zero` stored stale stack instead of 0. wasm2c
  clears structs with x0 stores; the MOD player's channel table came out as garbage on
  rv32 (found with a players-only firmware in the cycles sim, bisected to the emulated stores). Fixed (`sw zero, 0(sp)`);
  every `aligned` board and cycles image built before it may have stored garbage on a
  misaligned zero store (carts: rare, their hashes passed).
- **Vivado** (`--sys-mhz 100 --comp-mhz 100`, `build/soc_z7_audio`): timing met, WNS
  +0.139 ns, WHS +0.024 ns, after registering the PCM multiplier's gain operands (the
  path c -> LUTRAM -> min() -> DSP missed by 54 ps). 8,602 LUT (48.9 %), 9,592 FF,
  34.5 BRAM tiles, 10 DSP; `zm_audio_soc` 1,375 LUT + 9 RAMB18 + 4 DSP, `zm_hdmi_out`
  597 LUT.
- **On the board** (tutorial, `ZM_BLIT=sw`): the cart runs; after 5 s `md.l 0x05ffff80 8`
  read status 0 (nothing late, nothing dropped), resyncs 0, the core at 44.1 kHz
  (223,809 samples in 5.07 s), 584 writes a second (sos.sndh's 12 a tick at 50 Hz).
  **Not yet heard**: Matt listens.

---

## 2026-10-04: the picture bug hunt, and what it taught us

Milestone 7, the first cart (`tutorial`) running at 60 fps from DDR, came with a
broken picture: half the columns wrong and the colours off. Finding out why took a
night and about ten bitstreams. Most theories were wrong, and the wrong ones are kept
here because each one taught something.

### Solved (2026-10-09): the first clean picture on the monitor

The tutorial cart runs at 60 fps on the monitor, clean (milestone 8), built with **Vivado 2026.1**
(`fpga/build/board_hp/zm_hp_vivado_fetchsync_80.bit`). Three more lessons after the night below:
- **The primitive self-test settled the openXC7 question in 3 ms** (`make prim-test`, 39/45 pass):
  RAMB36 SDP x72, RAMB36 TDP x9 (the parity bit) and SRL16E/SRLC32E fail on silicon. `-nosrl` removed
  the last vertical lines; a remaining shear under openXC7 vanished under Vivado with the same RTL.
- **Vivado is the oracle:** synth + P&R in ~3 min (openXC7: 19+ min for this netlist), timing on every
  path. Two RTL lines Yosys accepted needed fixing (`wire a, b = …`; a function named `cell`).
- **The last bug was ours:** `zm_video_scanfetch.v` could lock the scanout fetch ~88 lines out of phase
  with the beam (HP1 is held until CTRL.RUN, which lands mid-frame, and a remembered VBL kept restarting
  it early), so every line showed black. Now the fetch waits for a fresh VBL and locks within a frame.
  Found without an ILA (the free licence refuses debug cores) by a netlist ECO that routed the scanout
  state to the glass SCRATCH register, read from U-Boot.

### What it was

- **The real cause: openXC7 writes a wrong bitstream for a RAMB36E1 in 72-bit SDP
  mode.** The A half (bits 0-35) of every word is wrong on silicon. Yosys picks that
  mode for any inferred RAM wider than 36 bits. Here that was the compositor's 48-bit
  accumulator and the 64-bit plane fetch buffer. Simulation, gate-level included, gets
  that mode right, so no sim could ever show the bug.
  - **Fix:** `rtl/video/zm_video_sdpram.v` builds any RAM wider than 32 bits from
    ≤32-bit slices (RAMB18s, which work). Proven in sim; the board check is pending.
  - **Rule:** under openXC7, never let Yosys infer a RAM wider than 36 bits.
- **A second fault: nextpnr does not time the PS7's HP pins.** Its timing report has
  no path through the PS7, so the logic between the HP ports and the fabric meets
  timing or not by luck of placement. The CPU running on some builds of an identical
  netlist and not on others fits that.
  - **Fix:** a register slice on every HP0/HP1/HP2 channel at the PS7
    (`soc/zm_board_mem.py` `hp_slice()`), so each pin meets one flip-flop.

### Theories that were wrong, in order

| # | Theory | What we tried | Why it was wrong |
|---|---|---|---|
| 1 | A 32-bit AFI write channel drops the upper half of each 64-bit write beat | WR32: every write as 4-byte beats, AFI `WRCHAN_CTRL = 0xf01` | Real (UG585 5.3.6), and kept, but not this bug. The diagnostic firmware showed CPU stores and plain row writes were exact |
| 2 | The sys→comp LUTRAM crossing queue on the read path | That queue in flip-flops, plus a read probe | The probe showed the data arrives intact on both sides of the crossing |
| 3 | The LUTRAM write queue | Two copies of the write queue (LUTRAM and FF) plus a write probe | That bitstream killed the CPU outright, at 100 and at 80 MHz (likely the untimed HP pins) |
| 4 | An untimed clock crossing | sys and comp on one 80 MHz clock, every path timed | The picture stayed wrong. On a clean port, the output was byte-for-byte identical to the two-clock build. That ruled out queues, CDC and placement, and pointed at something deterministic |
| 5 | The CPU dies from a failed sys timing | A rebuild at sys 80 that met timing | The CPU still didn't run. The cause was elsewhere (see the HP pins) |

### The trap that wasted half the night: a wedged HP port

A PL reload in the middle of a DMA write burst left the HP1 AFI (on the PS side)
waiting for data beats that never came. **That survives every PL reload.** From then
on, every HP1 write hung, on every bitstream, so every result after that point
measured the wedge, not the RTL. `hp-test` exposed it (HP0 raw writes fine, HP1 hung
with 0 beats), and an RST KEY cleared it.

- **Rule:** before any reload, stop the cart (`mw.l 0x43c00008 0`) and wait for the
  DMA to go idle.
- **Fix:** the video DMA now waits for CTRL.RUN, and CTRL 0 drains it to idle
  (`soc/zm_video_axi.py` `enable`). A fresh bitstream can't talk to an unconfigured
  AFI, and a reload never cuts a burst.
- **Open:** the first gated bitstream stalled the CPU at boot (CART_STATE 1, no
  mailbox). That build predates the HP slices.

### What worked as debugging tools

- **The diagnostic firmware** (`cycles/bdiag.c`): a mode word in DDR picks a
  self-test instead of the cart, so there is no rebuild per question. diag5 also
  writes `5A<wait#><STATUS>` to CART_BEAT while it waits, so a hang shows which
  status bit never came.
- **Probes in CSRs** (`soc/zm_hp_probe.py`): latch the first beats at RDATA and
  after the crossing. One run tells the AXI side from the PL side.
- **`make hp-test`**: a small design with raw AXI engines on HP0/HP1 and the real
  `ZMVideoAXI`. It builds once, in about 7 min; after that every DDR-port question
  is a few U-Boot `mw`/`md`. It found the wedge and cleared the AXI side.
- **`board_shot.py`**: a screenshot through U-Boot from the debug mailbox, no camera.
- **Comparing two builds byte for byte**: identical output from very different
  netlists means a deterministic cause (a primitive, a protocol), not timing.

### The tooling we lacked (each would have cut hours)

1. **A primitive self-test bitstream.** One design that uses every primitive and
   mode the SoC uses (RAMB36 SDP x72, RAMB18, the LUTRAMs, SRL, DSP, carry, ODDR),
   each checking itself against a pattern and reporting over GP0. Run it once per
   openXC7 version, and the x72 bug shows in minutes. openXC7 has now failed us
   twice on a primitive mode (the OSERDES cascade, the x72 RAM).
2. **A primitive allowlist in `make check`.** List the cells and modes Yosys
   inferred, and fail on any not yet proven on silicon by (1).
3. **An on-chip logic analyser.** LiteScope (part of LiteX) captures chosen signals
   into BRAM on a trigger, readable over GP0 from U-Boot. One capture of the
   accumulator RAM's input and output would have shown the bug directly, instead of
   a hand-made probe CSR per theory.
4. **A board preflight.** Before any SoC test, run `hp-test` raw writes and reads
   on every HP port. It would have caught the wedged HP1 before the night's runs
   instead of after.
5. **One command per board run.** Load, AFI, loadx, crc, run, probe and shot as a
   single script with a pass/fail result. Doing it by hand cost time and caused
   mistakes (stale prefills, a reload mid-burst).
6. **A lint that every PS7 pin goes through a register.** nextpnr doesn't time them.
7. **A Vivado cross-check** of the same RTL. If it works there and not with
   openXC7, it's the toolchain. The WebPACK edition covers the 7010.

**1 and 2 are built (2026-10-04), not yet run on the board.**
- `make -C fpga prim-test` (`rtl/board/prim_test_top.v`, `rtl/board/prim_test/`): one lane per mode, each an
  INFERRED memory or operator written the way the SoC's RTL writes it, so Yosys maps it to the mode
  under test (45 lanes): RAMB36 SDP x72 (512 and 256 words, 8 byte enables), RAMB18 SDP x36 (512 words, a
  256-word memory, words 256-511 and 384-511 of 512, 9- and 8-bit byte enables), RAMB18/RAMB36 TDP
  at every width (x1 to x36), and every width that has bytes (x16/x18, x32/x36, x72) with per-byte
  write enables too, 9-bit and 8-bit, one-port write-first (2 byte enables, as
  VexRiscv) and read-first, the ROM, RAM32M, RAM64M, SRL16E, SRLC32E, the 11 DSP48E1 configurations
  of the SoC and blitter netlists plus a multiply-accumulate, CARRY4, MUXF7/MUXF8. Each writes an
  LFSR pattern and its inverse, reads back and compares with a reference built in the fabric
  (another LFSR, a shift-and-add multiplier, a bit-serial adder); results on GP0 for U-Boot
  (`tools/prim_test_read.py`, which also names the failed byte lanes; `boards/microphase_z7_7010/README.md`
  "prim-test"). All 45 pass in
  CXXRTL (`tests/test_rtl_prim_test.py`); a reference bit inverted in any of 10 lanes, one of each
  kind, is reported as that lane failing alone (`ZM_RTL_BREAK=1`). 12 k LUT, 11 k FF, 25 BRAM,
  11 DSP; about 7 min to build.
- `tools/prim_allowlist.py` + `fpga/silicon_prims.json`: every cell type, and for block RAMs and
  DSPs every mode (widths, write modes, write-enable count; OPMODE and registers), with a status:
  proven, pending (a prim-test lane covers it, no board result yet), suspect, bad. Seeded from the
  running cart SoC (`soc_z7_gated`), with SDP x72 bad, SDP x36 suspect, and every block RAM with
  per-byte write enables suspect (board: RAMB18 TDP x18 with byte WE lost byte lanes 1, 2, 6 of a
  64-bit word). The write-enable pattern is part of the key (`we1` whole word, `we2/4/8` byte
  enables: the count of distinct nets on WEA/WEBWE).
  `tests/test_prim_allowlist.py` fails `make check` when the board SoC netlist uses a bad mode or
  one never on silicon; pending and suspect are warnings (`--strict` makes them errors).

### The build loop (`fpga/BUILD_LOOP.md`)

- **Every build prints its stage times** (`build/build_times.txt`). Placement is
  55-70 % of a 4-6 min full build.
- **`make sweep SEEDS=…`** runs P&R on an existing netlist, two seeds at a time.
  Its 900 s cap is too short for a 15K-cell netlist: four of six seeds hit it.
- **`make soc-dev`** replays the previous placement. That saves time only on an
  identical netlist (64 s instead of 226 s of P&R); after a real edit it saves
  nothing, because Yosys renumbers cells everywhere. The fix would be to synthesise
  each module separately; not done.
- **Every nextpnr run is capped** (`OPENXC7_PNR_TIMEOUT`, 1500 s): an uncapped HeAP
  placement once ran 52 min.
- **Size is speed:** the FF crossing queues (+4.3K FF) grew the netlist from 9.4K
  to 15K cells. Full builds went from 4-6 min to 25+ min, and the `--blit` build
  could no longer place ("Unable to find legal placement … SLICE_FFX"). Those queues
  turned out not to be the cause, so they go back to LUTRAM once the RAM fix is
  confirmed.

### Board rules learned (also in `fpga/boards/microphase_z7_7010/README.md`)

- Load the PL BEFORE touching the AFI registers (`0xF800_8000`…), or the ARM hangs.
- Never change an AFI width while PL traffic runs.
- Never reload the PL while an HP DMA may be mid-burst (see the wedge above).
- After a reset, U-Boot's network-boot retry loop can ignore a single Ctrl-C.
  Sending Ctrl-C every 0.1 s across the reset catches the countdown.

---

## 2026-10-03: the board is alive

| # | On the real board | What it proves |
|---|---|---|
| 1 | **LED blink** (`make -C fpga blink`) | the open toolchain (Yosys → nextpnr → prjxray → openFPGALoader) end to end on silicon |
| 2 | **HDMI test pattern** (`hdmi-test-oddr`) | the video path at 800×600@60, through an ODDR serialiser (the OSERDES cascade fails under openXC7) |
| 3 | **U-Boot + DDR** (zeST `BOOT.BIN` on SD) | the ARM side boots; DDR3 512 MB at 533 MHz; `mtest` clean |
| 4 | **HDMI audio** (`hdmi-audio-test`) | data islands + InfoFrames + ACR: a 440/660 Hz stereo tone from the monitor's speakers |
| 6 | **The YM2149 plays "Drooling" by 505** (`ym-test`) | jt49 from a BRAM register dump, the audio core (YM + 4-ch PCM + mixer), 44.1 kHz over HDMI with exact alternating CTS: real ST music from the hardware YM |
| 5 | **The OSD, driven by the ARM** (`osd-test`) | GP0 at `0x43C0_0000` from U-Boot (ID `5a4d474c`, scratch read-back), "HELLO FROM THE ARM" + the time, OSD on/off, recoloured live |

- **First light.** `openFPGALoader -c digilent_hs2 --detect` sees the JTAG chain:
  the ARM Cortex-A9 DAP (`0x4ba00477`) and the **xc7z010** (`0x3722093`).
- `fpga/build/blink/blink_top.bit` (openXC7, 8 LUTs) loaded into the PL SRAM.
  **PL LED1 and LED2 alternate**, as designed. The open toolchain
  (Yosys → nextpnr-himbaechel → prjxray → openFPGALoader) is proven end to end
  on real silicon.
- Setup: the USB-C **JTAG** port (J6; it also powers the board), the **UART**
  port (J3, CH340 → `/dev/ttyUSB0`), and jumper **J1 on the JTAG pins**.
- **HDMI audio works** (`make -C fpga hdmi-audio-test`): HDMI (not DVI) with
  data islands (TERC4, guard bands, BCH ECC), AVI + Audio InfoFrames, ACR
  N=6144/CTS=40000, 48 kHz stereo L-PCM: 440 Hz left, 660 Hz right **heard from
  the monitor's speakers** (the Z7-Lite has no other audio output). The encoder
  (`rtl/hdmi/`) is ~370 LUTs; its packets equal hdl-util's bit for bit, and a
  reference sink in the testbench decodes 3 frames (14 break tests).
  `make -C fpga edid-test` shows a monitor's EDID as hex on screen
  (`tools/edid_decode.py` decodes it).
- **The machine's sound, built for the board** (`make -C fpga ym-test`, not yet
  loaded): HDMI audio at **44.1 kHz with exact timing** (N 6272, CTS measured
  from the sample strobe's own accumulator: 44444/44445, the average exact), the
  audio core (`rtl/audio/`: jt49 as the ST's YM, the four Paula channels, the
  machine's mix; **PCM sample-identical to the Zig machine**, 1,270 LUTs) and a
  bitstream playing "Drooling" (505) from a YM dump in BRAM. The ABI as
  registers, the verification and the YM findings (jt49 is closer to a real ST
  than `ym.zig`, whose envelope shapes 11 and 15 hold at the wrong end):
  [`FPGA_AUDIO.md`](FPGA_AUDIO.md).
- **HDMI works** (`make -C fpga hdmi-test-oddr`): 800×600@60 colour bars, the
  bouncing box and the 8-bit ramps on a monitor, from the PL alone. **Finding:**
  the OSERDESE2 10:1 master/slave cascade (`zm_dvi_out`) routes correctly under
  openXC7 (it was checked in the FASM) but gives **no signal on silicon**. A
  fabric shifter at 200 MHz into an ODDR (2 bits a clock) works, and that
  serialiser replaces it in the SoC. Variants for future debugging:
  `hdmi-test-{clkonly,lvcmos,rev,inv}`.
- **The SoC now uses it.** `zm_dvi_out` serialises with a fabric shifter
  (`rtl/video/zm_tmds_shift.v`, 200 MHz) into an ODDR by default; the
  OSERDESE2 cascade is kept behind `SERIALISER="OSERDES"`. CXXRTL test of the
  shifter behind the encoder (bit 0 first, two bits a 5x clock, all five
  counter phases) with 3 break tests. The new netlist re-drew the seed (seed 8:
  sys 93.1, comp 107.5 MHz); over seeds 1-5 the best is **seed 5, now pinned:
  sys 102.3 MHz, comp 118.4 MHz (misses 125), pix 117.5, pix5x 361.4 (needs
  200)**. `fpga/build/hdmi_oddr_soc/results.txt`.
- **The ARM side and DDR work.** With zeST's 7010 `BOOT.BIN` alone on the SD card
  and J1 on SD: the FSBL and U-Boot 2025.01 come up. The console is the CH340 at
  **921600 baud** (not 115200). The ARM runs at 666 MHz; **DDR3 is 512 MB at
  533 MHz**. `mw`/`cmp` and `mtest 0x01000000-0x02000000` show 0 errors.
  Ctrl-C stops the PXE autoboot at the `Zynq>` prompt. `fpga/tools/uboot.sh`
  sends commands. **Note:** at the prompt, U-Boot reserves `0x1dac9f20-0x1fffffff`
  (itself, its stack and its FDT), which overlaps the glass's cart window at
  `0x1E00_0000`. Under Linux with `mem=480M` that is fine, but a cart loaded
  from U-Boot must go lower.
- **The OSD test bitstream: WORKS ON THE BOARD.** Matt saw the banner at load;
  `osd_uboot_demo.sh` then read ID `5a4d474c`, VERSION `00010100`, CTRL `2`,
  SCRATCH `c0ffee42` back over GP0; "HELLO FROM THE ARM" and the time appeared,
  the box went off and on, and turned yellow-on-blue (FG/BG read back
  `00ffff00 000000aa`). openXC7 timing: pix 120 MHz, pix5x 505 MHz (need 40/200).
  `make -C fpga osd-test` → `build/osd_test/osd_test_top.bit`: the test pattern
  with the glass OSD over it (`zm_glass_osd`), and `zm_glass_regs` on the PS7's
  M_AXI_GP0 at `0x43C0_0000`, clocked from the PL's 40 MHz pixel clock (not FCLK0).
  The PL writes a banner into the OSD text RAM at reset (`rtl/board/osd_banner.v`)
  and CTRL starts with the OSD on, so the overlay shows at load even if GP0 does
  not. `fpga/tools/osd_uboot_demo.sh` then reads the ID, writes "HELLO FROM THE
  ARM" and the time, toggles the OSD and changes its colours from U-Boot. CXXRTL
  plays those steps and checks every pixel of a frame after each
  (`tests/tb/osd_test_tb.cpp`, 5 break tests); `make -C fpga osd-test-sim` draws them
  (`build/osd_test/osd_*.png`).

### The first cart, built for the board: main RAM and video in PS DDR over HP0/HP1

No Linux: U-Boot puts the firmware image in DDR, the PL is loaded over JTAG, and
a GP0 write releases the cart CPU (procedure: `fpga/boards/microphase_z7_7010/README.md`,
"Running a cart from U-Boot"; files in `fpga/build/board_hp/`).

- **Memory** (`soc/zm_board_mem.py`): the cart CPU's 32 MiB main RAM at bus
  `0x4000_0000` IS PS DDR `0x0400_0000` (free under U-Boot). The CPU reaches it
  on **S_AXI_HP0** through `soc/zm_hp.py` (32-bit Wishbone -> 64-bit AXI3; a
  cache-line refill is one 4-beat burst, a store one blocking write), the video
  DMA on **S_AXI_HP1** through `soc/zm_video_axi.py` (bursts of 16, pipelined,
  never across 128 bytes). One PS7 instance carries GP0 + HP0 + HP1. No boot
  ROM: the reset vector is the window's first word, the CPU held in reset by the
  glass until CTRL.RUN. No posted-write buffer yet (the 8-entry one CYCLES.md
  recommends is next).
- **Firmware** (`cycles/bmain.c`, `cycles/bboard.c`, `make board-fw CART=..`):
  the sequencer firmware of the video sim, linked for the board's CSR map
  (checked equal to the sim's by `tools/cycles_csr.py --hp-check`); it reports
  CART_STATE / CART_BEAT through the glass, prints nothing.
- **Sim** (`soc/hp_sim.py`, `make hp-sim CART=tutorial`): the same SoC and the
  same board core, with a DDR model behind HP0/HP1 (20-clock first beat, answers
  only inside the window, poisons writes on a WLAST/AWLEN mismatch) and a
  "U-Boot" that writes CTRL.RUN over GP0. **tutorial: frames 5 and 10 hash =
  scene_hash.mjs = native**, no underrun; 1.40-1.65 M sys clocks a frame at
  100 MHz (60 fps). 7 Migen tests, 3 of them mutants (lane select, wrong DDR
  map, late WLAST), all caught.
- **Bitstream** (seed 5, `fpga/build/board_hp/zm_hp_s5_comp125.bit`): sys
  **109.5 MHz** (pass at 100), comp **121.7** (misses 125 by 2.6 %), pix 130.8,
  pix5x 458.5. 10,600 LUTs (30 %), 7,084 FFs, 9 RAMB36 + 16 RAMB18, 17 DSP.

### On the board: the cart runs at 60 fps; every odd picture column was never written (fixed: WR32)

- First load (`zm_hp_s5_comp125.bit`): CART_STATE 2, CART_BEAT ~60/s, the
  tutorial's layout and colours in place, but **every second column pure black**:
  the upper 32-bit half of every 64-bit WRITE beat never reached DDR, on HP1
  (pictures) and on HP0 (the CPU's stores into VRAM: the staggered block, the
  broken checker at the bottom). Reads of both halves were fine (the CPU runs code
  from odd words). The RTL and the routed netlist drive all 64 WDATA bits and
  WSTRB 0xFF; UG585 5.3.6: a 32-bit AFI write channel "expands" an 8-byte beat and
  keeps WDATA[31:0] only, which is exactly this.
- **Fix (WR32):** every write is now 4-byte beats on WDATA[31:0] / WSTRB[3:0]
  (the DMA sends a 64-bit beat as two, bursts of 16 aligned to 64 bytes, which
  the AFI upsizes), and U-Boot sets both AFI write channels 32-bit
  (`WRCHAN_CTRL = 0xf01`); reads stay 64-bit. The sim's DDR model now runs its
  write channels that way: the old RTL reproduces the black columns there
  (`tests/test_board_mem.py`, a break test), the new one hash-matches tutorial
  (frames 5, 10 = scene_hash). `zm_hp_wr32_s5_comp120.bit`: sys 109.5, comp
  120.2 (at 120), pix 136.4, pix5x 462.5 MHz, all pass.
- **WR32 did not fix it; the diagnostic narrowed it** (`cycles/bdiag.c`, a mode
  word in DDR picks a test instead of the cart, no rebuild): CPU stores and loads
  over HP0 are exact (modes 1, 2). A BG pass writes its row exactly (mode 3), and
  AWCACHE 0 vs 0b0011 changes nothing. Only a pass that READS through the
  compositor's read port (mode 4, a MIX of a known row) is wrong: even pixels
  are constants (`0054aa55` / `00fdfeff`), odd pixels keep bits 44-55 and lose
  bits 32-43 to constants. The constants depend only on the beat's parity, never
  on the data, so no AXI lane, size or width setting can produce them.
  - The fault is in the PL between RDATA and the mixer. The RTL sim, and a
    gate-level sim of that path's Yosys netlist (RAM32M models, `fpga/build/gl_queue/`), are both exact. So it
    arises after synthesis (placement, routing or bitgen of the sys->comp LUTRAM
    queue under openXC7) or on silicon.
  - Next bitstream: that one queue in flip-flops (all four did not place: a
    52-min placer stall, now capped by `OPENXC7_PNR_TIMEOUT`), plus a probe CSR
    (`soc/zm_hp_probe.py`) that latches the first two beats at RDATA and at the
    queue's output, so one run tells the AXI side from the crossing.
- **ROOT CAUSE (2026-10-04): wide block RAMs.** With a clean HP1 (after an RST; a
  burst cut by a PL reload had wedged its AFI overnight, and that survives reloads), the
  mode-4 output was byte-identical on a two-clock LUTRAM build and a one-clock FF build,
  so it was neither the queues, the clock crossing nor the placement. The read probe was
  clean, and hp-test replaying ZMVideoAXI's exact write pattern on HP1 wrote DDR
  perfectly. The bad bits are 0-35 of the compositor's 48-bit accumulator word
  ({pix1 RGB, pix0 RGB}): exactly the A half of a RAMB36E1 in SDP 72-bit mode, which
  is how Yosys maps any RAM wider than 36 bits (the accumulator, and the plane fetch
  buffer `u_fbuf`, 64-bit). The 36-bit SDP RAMB18s (the line buffers) work. Simulation,
  gate-level included, models the primitive right, so this lives in the openXC7 /
  prjxray bitstream for that mode. Fix: `rtl/video/zm_video_sdpram.v` builds anything
  wider than 32 bits from <= 32-bit slices (RAMB18s).
- **Screenshots without a camera:** a debug mailbox at DDR `0x05ff_ff00`
  (`cycles/bmailbox.h`: fixed picture addresses, frame count, PFB, a freeze
  handshake) and `tools/board_shot.py` (U-Boot `md.l`, checked line by line,
  PNG); `HOST_DUMP_PFB` on the native host gives the expected PFB to compare with.

## 2026-10-03

- **The blitter, in RTL, standalone** (`fpga/rtl/blitter/`, `docs/BLITTER_HW_SPEC.md` §10): FILL, BLIT, LINE, TRIANGLE with the register block and `CYCLES`, behind separate read/write ports. `machine/blitter.zig`, run natively, is the oracle: **910 scripted ops + 8,200 random ones**, each in two memory-timing modes, identical in memory, `CYCLES` and `STATUS` after every op; 23/23 break tests caught. **2,596 LUT, 1,340 FF, 0 BRAM, 8 DSP**; 1 pixel/clock for a plain fill or line, 4-6 clocks for the read-modify-write ops (single-word v1, pipelined reads and bursts next). Not on the SoC yet (HP2, a snoop on the store buffer, `hwBlit` = write `COMMAND` and poll).

### Timing pass 2: the compositor on its own clock, the predictor on trial, a pinned seed

Details: [`fpga/README.md`](../fpga/README.md) "Timing under openXC7" and
[`fpga/CYCLES.md`](../fpga/CYCLES.md) "Branch prediction and the clock".
Logs and the ledger: `fpga/build/timing2/` (`results.txt`).

- **The board build meets timing:** `uv run python -m soc.zigmachine_soc
  --target z7 --build` gives **sys 100.63 MHz, comp 125.19 MHz** (both pass),
  reproduced by a fresh end-to-end build (same netlist byte for byte, same
  result). The seed is pinned in `soc/openxc7.py`: over seeds 1-12 the same
  netlist gives sys 76-102 MHz, and seed 8 is the only one that meets both
  clocks. Any netlist change needs a re-sweep.
- **The compositor runs in `comp`** (`soc/zm_z7.py`'s PLL, 125 MHz), crossing to
  `sys` through `soc/zm_video_cdc.py`: snooped stores through a gray queue
  (`drained` = the compositor has used them), command/ready/painted as echoed
  toggles, read-back and the three DMA ports as toggle requests with queues.
  5 Migen-sim tests at unrelated clocks; the video sim (comp 200 against sys
  160) still hash-matches on tutorial and dhs_0pxl0reg; `make -C fpga check`
  green (122 passed).
- **comp's own path** was the plane pass's geometry (latch LUTRAM -> compare
  -> carry chains, 10-11 ns). `zm_video_plane.v` now registers its inputs and
  its geometry before `start`: comp 89-99 -> 92-139 MHz (median 112) over the
  seeds. RTL video tests 46/46.
- **No branch prediction loses.** It removes the static predictor's cone (pass
  1's 82 -> 99.5 MHz, one seed each), but on this netlist that is worth ~10 %
  sys at the median seed (90.7 -> 99.9 MHz) against **+16.5-24.5 % cycles**
  (union_beatdis 52 -> 62 MHz needed, ulm_dsots 98 -> 114, skystrike 119 -> 141,
  tutorial 26 -> 32). The board keeps static prediction; the no-prediction core
  is built alongside (`make -C fpga vexgen-board`, `vexgen/gen.sh ...:nopred`).
  The dynamic-target predictor needs 9-14 % FEWER cycles but does not route
  (overuse climbs, three attempts).
- **Is ~100 MHz enough?** For union_beatdis (52), tutorial (26) and ulm_dsots
  (98, 3 % margin) yes; **skystrike (119) no**, about 50 fps on its sustained
  load. Plus the sequencer's own wait for the passes, which comp's faster clock
  shortens.
- **Not done:** a frozen placement. openXC7's `-o preplaced=` aborts on this
  build (`dict::at()` while packing, even with one pinned cell), so the seed is
  the only pin.

**Pass 3 should look at:** routing the dynamic-target core (it would take
skystrike to 107 MHz needed); the `-o preplaced=` crash (a frozen placement
would stop every netlist change from redrawing the seed lottery); VexRiscv's
execute-stage and I$-tag->regfile paths, now `sys`'s limit; and Vivado for one
honest timing report.

---

## 2026-10-02 (night)

### The video composites into a DDR framebuffer (ADR 2026-10-02; Fable #1, 4-9)

The line-racing compositor is gone. Every frame is built in the machine's own
order, at the compositor's speed, into a picture in memory, and the scanout shows
the previous picture. Details: [`fpga/rtl/video/README.md`](../fpga/rtl/video/README.md).

- **The sequencer is the cart CPU's firmware** (`fpga/cycles/vseq.c`): hwClear's
  global handlers and BG passes, `frame()`, then per enabled plane LATCH and a
  PLANE pass a line with the handler called before it, exactly where and with
  the line numbers `machine/video.zig` uses. Handlers are calls, not interrupts.
  It waits for `painted` (the pass has read the CPU's state) and `drained` (the
  handler's stores have reached the compositor) before each pass.
- **Plane-major, so rows live in memory.** A BG pass stores its PFB row; a PLANE
  pass loads it, paints, folds it into the picture and stores both. The PFB rows
  land where the machine keeps its PFB, so `scene_hash` hashes the board's frame.
- **Double-buffered picture, swap at VBL.** PRESENT marks the back picture
  complete; a pass that would write a picture waits for the swap. No tearing, one
  frame of latency. The scanout fetch reads the front picture a line ahead in
  400-beat bursts; underrun is detected and sticky.
- **Memory:** 64-bit burst read/write ports; `soc/zm_video_dma.py` serves them
  (scanout first) over one Wishbone burst master, AXI-shaped (`max_burst` = 16
  on the board).
- **The region is snooped** (`soc/zm_video_snoop.py`): it stays DDR, so every
  cart load reads what wasm would; the CPU's stores to registers, palettes and
  the BEAM table reach the compositor at the store buffer's drain rate. The
  sequencer copies the compositor's 4 write-backs into the region.

**The integration test** (Fable #9; `make -C fpga video-sim`,
`tools/video_sim_run.py`): VexRiscv running the translated cart with the
sequencer, the RTL pipeline, the scanout in a 40 MHz pixel clock against a
160 MHz sys clock, and ONE shared main RAM with the board's memory-path model in
front of the CPU (`hp_sb`) and of the video DMA (24-clock first beat). 60 frames,
the PFB hash at frame 60 against `scene_hash.mjs` and the native host:

| cart | hashes (frame 60) | cart Mc | seq Mc | CPU max Mc | wall Mc | comp Mc | DMA Mc | CPU MB/frame | comp MB/frame | MB/s at 60 fps |
|---|---|---|---|---|---|---|---|---|---|---|
| tutorial | **= scene_hash, = native** | 0.48 | 0.68 | 1.16 | 2.60 | 0.77 | 0.58 | 0.32 | 3.39 | 276 |
| union_main | **= scene_hash, = native** | 48.16 | 1.76 | 61.72 | 49.96 | 2.45 | 4.02 | 18.11 | 11.09 | 1,806 |
| badflicker | **= scene_hash, = native** | 0.28 | 0.63 | 0.92 | 2.60 | 0.90 | 0.65 | 0.23 | 3.70 | 289 |
| equinox | **= scene_hash, = native** | 4.51 | 2.61 | 7.20 | 7.12 | 3.22 | 2.41 | 3.20 | 14.78 | 1,133 |
| dhs_0pxl0reg | **= scene_hash, = native** | 0.15 | 0.66 | 0.81 | 2.59 | 0.61 | 0.50 | 0.20 | 2.69 | 227 |

Cycles in millions of 160 MHz sys cycles (2.65 M = one 60 Hz frame); full notes in the README.

**Mutants.** The line-major sequencer fails on badflicker and equinox over 60 frames (tutorial, the control, still matches). The
no-drain sequencer does **not** fail: it issued thousands of commands with a
store in flight, on three memory configurations up to a saturated DDR, and
every hash matched, because a pass reads palettes only after its ~450-clock row
load and the next pass waits for the previous row store. The drain rule is kept
(free, and exact by construction), but no corpus cart makes it load-bearing.

**Timing (the seal agent's finding).** The snoop's dBus tap was the SoC's
critical path under openXC7 (79.4 MHz). Pipelined (tap, offset, compare, and a
registered output with the region decoded into select bits the compositor takes
as inputs, `TIMING_FABLE.md` P1-4) it is off it: 92.8-96.8 MHz, then limited by
LiteX's bus-timeout counter (removing the timeout gained nothing, 92.3: P1-5
dropped). A separate compositor clock (Fable's `comp150_sys100`: 117.6 MHz) is
the next cut, not done.

**Costs:** `zm_video_comp` 1,691 LUTs (+313), `zm_video_out` 1,960 (+468), BRAM
unchanged at 8; the z7 glass SoC 5,433 LUTs (30.9 %).

**Next:** overlap row I/O with the next handler (a second line buffer): 3-4 plane
frames need it to fit 60 fps (equinox: compositor 3.2 Mc a frame); the AXI HP
master and HP bridge; the cart CPU is the limit for union_main (48 Mc a frame of
`frame()`, as CYCLES.md found for its float code).

## 2026-10-02 (evening)

### The glass: the console's front panel ([`FPGA_GLASS.md`](FPGA_GLASS.md))

- **ARM stack:** Linux (Buildroot) running one static Zig program, `glass`,
  over `/dev/mem` (ADR 2026-10-02). zeST's `BOOT.BIN` and, as a stopgap, its
  kernel boot it.
- **PL:**
  - `zm_glass_regs` is an AXI3 GP0 slave with the cart CPU's reset, a key FIFO,
    the joypad and the cart's reports: 223 LUT.
  - `zm_glass_osd` is 32×16 characters of the ST system font over the finished
    picture: 45 LUT, 2 BRAM.
  - Whole SoC: 4,424 LUT (25.1 %).
- **Proven without the board:**
  - the RTL under CXXRTL, including 3 whole frames checked pixel by pixel, with
    13/13 break tests caught;
  - the loader, menu, keymap and pad against a simulated block;
  - the board images `fpga/cycles` links for 9 carts, which go through fat
    disks and `glass sim-load` and land byte for byte;
  - `boot.scr` byte-identical to `mkimage`'s.
- **The mouse** (added later the same day): a `POINTER` register, with presses
  latched until the firmware acks them and a `SEQ` the firmware polls, so the
  cart gets `pointer(x, y, buttons)` with the browser's rules (0..639 × 0..199,
  any button = bit 0, a double-click pulse = bit 1). `zm_glass_regs` is now
  254 LUT. Pads gained `xpad` and the Sony, PlayStation, Nintendo and Microsoft
  HID drivers.
- **The console page** (2026-10-03, Matt's must-haves): **cold reset** (reload
  from SD, window zeroed) and **warm reset** (`CTRL.WARM`: the CPU restarts over
  its memory; firmware hook `glass/firmware/glass_boot.c`, stubbed), a master
  **volume + mute** in a new `AUDIO_VOL` register (0x3C, VERSION 1.2.0) for the
  audio mixer to multiply in, persisted in `glass.cfg`; a live **debug page**
  (versions + git hash, CART_STATE/beat/fps, loads, uptime, DDR, XADC
  temperature, memory, the pad's name); **cart descriptions** from `shelf.txt`
  (`fpga/tools/shelf_meta.py`); the Linux side of an ssh shell over Ethernet.
  `zm_glass_regs` 245 LUT; 56 Zig tests, 26 RTL + 33 ARM/firmware break tests.
- **Open:** routing the SoC with the PS7 under openXC7 diverges (overuse 730 to
  1,830 over 51 iterations). Also open: the HP-port master and the board firmware
  that reports `CART_STATE`.

## 2026-10-02 (afternoon)

### The memory path, measured (`784cb2c`)

`soc/zm_memtiming.py` puts a DDR latency model in front of the simulation's
RAM. Its numbers are derived from UG585, UG1145 and the JBLopen benchmarks, not
measured on the board yet:

- an HP read: +24 cycles unloaded, +62 with DDR saturated, at 150 MHz;
- a blocking write: the same as a read;
- the options: a posted-write buffer, write combining, and ACP through the
  ARM's L2.

All 59 runs hash identically to the wasm machine.

| cart (aligned build) | 1-cycle RAM | HP, blocking stores | HP + 8-entry store buffer | ACP |
|---|---|---|---|---|
| union_beatdis | 55 MHz | 194 | 61 | 58 |
| ulm_dsots | 98 | 248 | 112 | 106 |
| skystrike | 115 | 325 | 129 | 124 |

- **Blocking stores were the whole penalty.** A posted-write buffer of about
  50 LUTs matches "free stores" cycle for cycle, so a write-back D$ is not needed.
- **A 16 KiB 2-way I$** costs +47 LUT and +3.5 BRAM, and brings skystrike to
  119 MHz. polkadots' I$ refills drop from 792k to 57k a frame.
- **Recommendation:**
  - VexRiscv `standard` + I$ 16K 2-way, D$ 4K write-through;
  - an 8-entry store buffer on HP0;
  - the aligned build (no bounds checks);
  - 150 MHz.

  Margin is 26 % unloaded, about 140 MHz under saturated DDR.
- **At board bring-up:** time one refill and one posted write, then put the real
  numbers in `tools/mempath_cfg.py`.

### A full frame on the wire (`f5b84e5`)

- **Mixer.** The browser stacks one canvas per plane. Chrome's software
  compositor was measured over all 65,536 colour × alpha pairs, and the RTL
  mixer reproduces it byte for byte (`zm_video_mix`). The C oracle equals
  Chrome's own screenshots.
- **Scanout.** The compositor runs in its own clock, with two dual-clock
  display line buffers feeding VESA 800×600 at 40 MHz. Whole frames are checked
  against VESA 800×600 timing, with the picture doubled vertically. An underrun
  is sticky.
- **HDMI.** Our own DVI TMDS encoder takes 52 LUTs per channel; 2 million
  symbols equal a spec encoder. Output goes through OSERDESE2 10:1 and OBUFDS.
- **The shelf.** All 90 hostable carts replay pixel-identically through the RTL.
  Line-by-line order (the hardware's) changes only `badflicker` (its noise seed
  is counted at `hwClear`) and `equinox` (planes share `RES_FLICKER`).
- **Throughput.** The worst line takes 5,060 compositor clocks: 4 % margin at
  100 MHz, 36 % at 150 MHz.
- **Open:** `frame()` running while the beam scans, the pass/HBL sequencer, and
  AXI HP bursts.

### The first bitstreams (`f685ee5`)

- **openXC7 in Docker**, pinned to toolchain-nix 092acc1. The xc7z010 chipdb is
  reproducible, and its sha256 is checked on every rebuild.
- **`make -C fpga blink`** builds `blink_top.bit`: 8 LUTs, 266 MHz against 50.
- **The full SoC** (VexRiscv, JTAG UART, PLL, video pipeline, HDMI serialisers)
  places and routes: 4,159 LUT, 46 BRAM, 17 DSP. Pixel clock: 126 MHz achieved.
  **sys: 92 MHz achieved against 100**, on VexRiscv's fetch path, where 9.17 ns
  of the 10.87 ns is routing. The fix is a lower sys clock or pipelining.
- **Fixed:** the generated XDC had no `create_clock`, so every clock was being
  checked against nextpnr's 12 MHz default, a false pass.

## 2026-10-02

### Step 0b-ii: the cart CPU's real load, and the verdict (`623f27c`)

The native host runs bare-metal on the SoC's own VexRiscv `standard` (rv32im) in
Verilator, built with GCC 13 and picolibc and a three-header shim for the stock
wasm2c runtime. **All 9 sample carts hash identically** to `scene_hash.mjs` and
to the native host, in every build. A cycle counter splits the time three ways:
**cart** (`frame()` plus the HBL handlers), **machine render**, and
**blitter**. The last two become RTL.

| cart | Mc/frame (p95) | MHz needed, soft-float | float share |
|---|---|---|---|
| blitter | 0.14 | 9 | 78 % |
| tsl_hybridglenz | 0.16 | 10 | 28 % |
| tutorial | 0.60 | 36 | 0 % |
| union_beatdis | 1.54 (2.04 worst frame) | 93 (122) | 0 % |
| ulm_dsots | 1.69 | 101 | 1 % |
| skystrike | 2.01 | 120 | 0 % |
| replicants_emlyn | 9.17 | 550 (209 even with an f64 FPU) | 65 % |
| polkadots | 37.7 | 2262 (449 with an f64 FPU) | 83 % |

- **Verdict: 150 MHz, no FPU.** The two outliers use `f64` kept from their
  JavaScript originals. That is a scene fix, not a hardware one.
- **Measured cheaper wins:** aligned loads cut cart cost by 4–40 %
  (union_beatdis 1.54 to 0.92 Mc). Dropping the bounds checks saves 36 %.
- **Caveat:** the simulated RAM answers in one cycle. With realistic DDR
  refill and store costs, union_beatdis would need 238 MHz, ulm_dsots 210 and
  skystrike 261. **The DDR/write path is the next design question**, more than
  the clock.
- **Still running:** the rest of the shelf (81 carts) is being measured in the
  background. `uv run python tools/cycles_report.py` refreshes the table.

### The video compositor in RTL, proven against the machine (`060a9af`)

`fpga/rtl/video/zm_video_comp.v` (+ 9 modules) builds each 800-pixel raster
line in passes: first the background or BEAM spans, then one pass per enabled
plane. It latches and reads registers exactly as `machine/video.zig` does.

- **How it was proven:** `tools/video_dump` records real carts through the
  native host: every register, palette and BEAM change around each HBL and pass,
  the memory read, and the PFB after each plane. The recorder's hashes equal
  `fpga/host`'s. A CXXRTL testbench replays the recordings with random memory
  stalls and compares all 800 pixels after every pass.
- **32/32 frames are pixel-identical.**
  - Real carts: tutorial, union_intro, union_main (3 planes), union_l16,
    tcb_colorshock, replicants_emlyn, gen4_3615, maxi, badflicker,
    dhs_0pxl0reg (BEAM), scroll, res_switch, medium_overscan.
  - Synthetic frames for what no cart reaches: fullscreen mode, per-line
    HSCROLL, BEAM edge cases.
- **25/25 one-rule mutants are caught**: `ZM_RTL_BREAK=1 make -C fpga test`.
- **Cost:** 1,169 LUT (6.6 %), 1,057 FF, 4 BRAM (palettes, line buffer,
  fetch), 1 DSP.
- **Throughput at 40 MHz (2,112 clocks a line):** 1 plane takes 858 clocks,
  3 planes 2,081. 4 planes need fetch/paint overlap or a 2× compositor clock.
- **Left:**
  - a scanout double buffer
  - the plane mixer (the browser stacks one canvas per plane)
  - an HBL sequencer: hardware runs line by line, the machine plane by plane
  - AXI bursts
  - place and route

### The board files: found, verified, and kept out of git

`fpga/tools/fetch_board.sh` (pinned commits, checksummed) fetches the following:

- **MicroPhase's own `Z7_LITE.xdc`.** It is in three public repos with an
  identical pin map (103 ports). Its header forbids publication, so it stays
  gitignored.
- **The schematic and the reference manual**, from MicroPhase's `fpga-docs`
  on GitHub.
- **Xilinx's xc7z010clg400 package file**, which maps each pin function to a
  ball.
- **zeST** (zerkman, GPL-3, an Atari ST on this very board): its Z7-Lite XDC,
  its Vivado PS7 configuration, and its **prebuilt 7010 `boot.bin`**.

What was verified:

- **HDMI pins:** every one was re-derived independently from the schematic and
  the package file, and all match: CLK U18/U19, D0 V20/W20, D1 T20/U20,
  D2 N20/P20, HPD P19, SCL R19, SDA T19. zeST agrees.
- **Clock:** the PL clock is 50 MHz on N18.
- **DDR3:** a single 16-bit MT41J256M16 (512 MB). One community `preset.xml`
  says 32 bits, and it is wrong.
- **UART:** it is on PS MIO, so the VexRiscv console on the board is `jtag_uart`.
- **`ps7_init` for the 7010** is not public. zeST's `boot.bin` brings up DDR,
  clocks and MIO without Vivado, and U-Boot then loads our bitstream. Our own
  FSBL needs Vivado or `xsct` run once on zeST's PS7 block.

### The whole SoC against the real board

`--target z7` now elaborates against `board.xdc`. Yosys `synth_xilinx` of the
whole design gives **2,408 LUTs (13.7 %), 1,874 FF, 4 DSP, and 19 + 8 BRAM**. The
design is VexRiscv `standard`, 32 KB ROM, 64 KB RAM, 8 KB SRAM, CSRs, JTAG UART,
PLL and `zm_vtiming`. Most of the BRAM is the on-chip test RAM, which moves to
DDR. The bitstream step stops only at openXC7's missing chipdb.

---

## 2026-10-01

### Toolchain: open source and installed

| Need | Installed | How |
|---|---|---|
| Synthesis | Yosys 0.69 (YoWASP, runs as wasm) | `uv` in `fpga/` |
| SystemVerilog to Verilog | sv2v v0.0.13 | `fpga/tools/setup.sh`, checksummed |
| wasm to C | wabt 1.0.42 (`wasm2c`) | `fpga/tools/setup.sh`, checksummed |
| SoC | LiteX 2024.12, migen (git), VexRiscv netlists, picolibc | `uv` |
| Simulation | Yosys CXXRTL (RTL tests), Verilator 5.020 (SoC), Icarus, GTKWave | CXXRTL via `uv`, the rest via apt |
| RISC-V software | riscv64-unknown-elf-gcc 13.2, picolibc; clang and zig cc as alternatives | apt |
| Bitstreams | not yet. openXC7 (Docker) first, Vivado ML Standard as the fallback | when there is a board |

Reused cores are pinned shallow submodules in `fpga/third_party/` (licences in
its README): `jt49`, `VexRiscv`, `neorv32`, `hdmi`, `fx68k`, and
`AtariST_MiSTer` as reference only.

### Measured block costs (Yosys `synth_xilinx`, xc7, before place and route)

| Block | LUT | % of 7010 | FF | BRAM | DSP |
|---|---|---|---|---|---|
| VexRiscv `min` (rv32i) | 1,041 | 5.9 % | 856 | 2 | 0 |
| VexRiscv `lite` (rv32im) | 1,718 | 9.8 % | 1,090 | 4 | 0 |
| VexRiscv `standard` (rv32im + caches) | 2,019 | 11.5 % | 1,363 | 9 | 4 |
| VexRiscv `full` | 2,399 | 13.6 % | 1,569 | 9 | 4 |
| `jt49` (YM2149) | 286 | 1.6 % | 291 | 0 | 0 |
| `fx68k` (68000) | 3,357 | 19.1 % | 1,441 | 2 | 0 |
| `zm_vtiming` (ours) | 64 | 0.4 % | 50 | 0 | 0 |

`hdl-util/hdmi` could not be measured: Yosys rejects its `real` parameters.
Reproduce with `make -C fpga util`.

### Step 0a: carts translate to RISC-V unchanged

`make -C fpga carts`: all 90 `docs/demo-*.wasm` go through wasm2c and compile
for `rv32imf` (zig cc, musl headers). The largest code sizes include each
cart's embedded data: `audio` 2.1 MB (the SNDH player's 68000 tables),
`mpp_truecolor` 1.2 MB, `joust` 0.9 MB. STNICCC is 83 KB.

### Step 0b-i: the whole machine runs as native C, byte-identical

`make -C fpga host-check`: `machine-video.wasm`, `rom.wasm` and each cart are
translated with wasm2c and linked against one shared 7 MiB bounds-checked
memory. The host replays exactly the call sequence of `apps/scene_hash.mjs`.

- **98 PASS, 0 FAIL:** all 89 carts at 1200 frames (sampled every 10) plus 9
  `--call` runs. The JSON matches byte for byte.
- `demo-audio` is refused by node too (memory max 48 pages), so there is
  nothing to compare.
- **Weak spots, shared with `scene_hash.mjs`:** 10 runs show one distinct frame
  for the whole run. stniccc and stream get no disk data (`diskReadBlock`
  returns 0), and gem, st_replay, fullscreen, north_south, dhs_0pxl0reg,
  ulm_dsots and the 3 step-1 `--call` runs probably wait for input. Real tests
  of those need disk serving or scripted input.
- `-ffp-contract=off` is mandatory: an F-extension `fmadd` would round
  differently from wasm.

Commits: `c007033` (doc), `da85e28` (`fpga/`), `a4d086d` (host).

---

## Open decisions for Matt

- **FPU and 7010 vs 7020:** decided by step 0b-ii's table (below, when it lands).
- **GPL in the bitstream:** `jt49` and `fx68k` are GPL-3, so a bitstream that
  contains them is a combined work. That is fine on your bench, but it needs
  deciding before you distribute one.
- **The board package:** `board.xdc` and `ps7_init` go into
  `fpga/boards/microphase_z7_7010/`. Nothing past simulation can start without
  them.
- [FPGA_TUTORIAL.md](FPGA_TUTORIAL.md): running your Zig screen on the real board, step by step.
