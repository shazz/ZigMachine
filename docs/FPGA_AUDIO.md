# The machine's sound on the FPGA

The sealed audio hardware of the ZigMachine (the YM2149 and the four Paula PCM
channels of [`machine/audio/`](../machine/audio/)) in RTL, played over **HDMI
audio at 44.1 kHz**, and checked against the Zig machine. The plan is in
[`ZIGMACHINE_IN_FPGA.md`](ZIGMACHINE_IN_FPGA.md) (the audio section); progress is
logged in [`FPGA_STEPS.md`](FPGA_STEPS.md). Sources: `fpga/rtl/audio/`,
`fpga/rtl/hdmi/`, `fpga/rtl/board/ym_test_*`, tests in `fpga/tests/test_rtl_audio.py`.

## 1. 44.1 kHz over HDMI, exactly

The sink rebuilds the sample clock from Audio Clock Regeneration packets:
`128 fs = f_TMDS x N / CTS`. At 40 MHz and 44.1 kHz the spec's N is 6272, so
CTS = 40e6 x 6272 / (128 x 44100) = **44444.44...** (400000 / 9): no integer.

`zm_hdmi_acr` makes the sample strobe and the CTS from **one** fractional
accumulator on the pixel clock (`+441 mod 400000` a clock; 48 kHz is `3 / 2500`):

- the strobe releases one sample at exactly 44.1 kHz on average;
- every N / 128 = 49 strobes, CTS = the pixel clocks those 49 samples took.
  That is how a real source measures it: **four 44445s and five 44444s in every
  nine periods**, and the sum of the CTS values is the clocks elapsed, exactly;
- `zm_hdmi_packets` sends each measured CTS once (an ACR packet on the next free
  island slot), not on a fixed line schedule, so the sink's average is exact.

`zm_hdmi_tx` takes `RATE_INC / RATE_MOD / ACR_N / CS_48K` (the IEC 60958
channel-status rate bits) and asks its source for each sample (`aud_req`); 48 kHz
remains the default. The 48 kHz tone bitstream (`hdmi-audio-test`) is built from
the same modules, so a rebuild now sends one ACR a CTS period (40000 every time)
instead of one every 32 lines; the `.bit` heard on the monitor predates this.

**Verified** by the reference HDMI sink (`tests/tb/hdmi_decode.h`,
`hdmi_packet_check.h`): at 44.1 kHz over 12 frames (8,774 samples, 179 ACR
packets) every CTS is 44444 or 44445 and the running sum never strays more than
**0.556 clock** from the ideal; every sample of the tone arrives, in order, none
dropped or repeated; channel status says 44.1 kHz. 48 kHz: CTS is 40000 every time.
Break tests: CTS off by one, wrong N / 128, wrong rate, a CTS sent twice, wrong
channel-status rate, a dropped sample: all caught.

## 2. The audio core (`fpga/rtl/audio/`)

| Block | What it does |
|---|---|
| `zm_audio_core` | the register block (below), the sample strobe and the YM's 2 MHz, both fractional enables of the system clock (44.1 kHz = 441 / 500000 and 2 MHz = 1 / 25 at 50 MHz) |
| `zm_audio_ym` | **jt49** (GPL-3, unmodified, a separate module) as the ST's YM: 2 MHz enable, SEL high, a period of 0 acts as 1 (`MUTE_NULL_PERIOD=0`, as the chip and ym.zig). Its output is averaged over each sample period (45 or 46 YM clocks): a box filter |
| `zm_audio_pcm` | the four Paula channels of `engine.zig`, one sample at a time through **one multiplier** (a DSP48): loop wrap, one-shot stop, step, volume, pan, the engine's exact order |
| `zm_audio_mix` | the machine's mix: Paula + YM x 0.33, clamp to [-1, 1], 16-bit = floor(x x 32768) |
| `zm_audio_fifo` | the clock crossing: 16-deep Gray-pointer FIFO, system domain to pixel domain, read one per `aud_req` after a half-full prefill |

### Exactly the machine's PCM arithmetic

`engine.zig` mixes in f32: `s = i8 / 128`, `gain = 0.5 x volume x min(1, 1 -/+ pan)`.
With volume = VOL / 256 and pan = PAN / 128 (the register forms), a channel's
contribution is, in units of 2^-23, the integer **i8 x VOL x min(128, 128 -/+ PAN)**:
at most 22 significant bits, and the sum of four stays under 2^24 units, so every
f32 product and partial sum in the engine is exact. The RTL computes the same
integers, so the two agree bit for bit for VOL 0..256 and PAN -128..128.

### The register map (the sealed ABI as registers)

The machine's audio ABI (`machine/sdk/audio.zig`) is functions, not registers.
The mapping, byte addresses, 32-bit words:

| Address | Register | ABI function |
|---|---|---|
| `0x000 + 4r` | YM register r (reads back the last write) | `machineYmWrite(r, v)`; R13 = 0xFF does not retrigger the envelope (and is not passed to jt49) |
| `0x040` | CTRL: write bit 0 | `machineAudioReset` (R7 = 0x3F, R8..R10 = 0, every channel stopped) |
| `0x044` | STATUS (sticky; any write clears): bit 0 a loop wrap overran, bit 1 a bad YM count, bit 2 a sample came late | — |
| `0x048` | VERSION = `0x00010100` | `ZM_AUDIO_VERSION` |
| `0x100 + 0x40c + 0x00..0x0C` | channel c: DATA, LEN, LOOP_START, LOOP_LEN (staged) | the arguments of `machinePaulaTrigger` |
| `+0x10` | STEP (16.16) | `machinePaulaSetStep` |
| `+0x14` | VOLUME (VOL / 256, 0..511) | `machinePaulaSetVolume` (f32 quantised) |
| `+0x18` | PAN (signed, PAN / 128) | `machinePaulaSetPan`, and the trigger's pan |
| `+0x1C` | POS (integer sample) | `machinePaulaSetPos` |
| `+0x20` | CTRL: bit 1 TRIGGER (staged fields go live, pos 0, active), else bit 0 = active | `machinePaulaTrigger` / `machinePaulaSetActive` |

`machineClear`, `machineMixPaula`, `machineRenderYm` and `machineClamp` have no
register: the core renders continuously. Timing within a sample: a write to POS,
TRIGGER or CTRL while that channel's sample is being mixed lands *after* the
sample (the mix's own `pos += STEP` or end-of-data stop gives way to it, per
field); VOLUME, PAN and STEP take effect at once, on a sample being mixed too. A write is accepted on `wr && ready`;
`ready` drops for a clock after a YM write and for 8 clocks of a reset. Lengths
and loop points are 24-bit (16 MiB of sample memory); a DATA address is a byte
address on the PCM memory port (`mem_req/addr/ack/data`).

## 3. Verification against the Zig machine

The oracle, `fpga/tests/audio_ref/audio_ref.zig`, imports `machine/audio/engine.zig`
unchanged and plays a stimulus script (YM writes, Paula calls, a register-dump
ROM, or a `.ymraw` as `ym_player.zig` does); the CXXRTL testbenches play the same
script into the RTL (`fpga/tests/tb/audio_script.h`) and compare.

| Test | Result |
|---|---|
| PCM: 13,466 samples: four channels clamping both ways, reset, POS and CTRL written mid-sample, then 60 random triggers / steps / volumes / pans / positions / activations (loops, one-shots, zero lengths) | **every sample identical** |
| The dump ROM vs the `.ymraw`, both in the Zig machine (3 s) | identical: the ROM's delta encoding loses nothing |
| YM script (tones, noise, envelope shapes 8 10 12 14 0 4 9 13, R13 = 0xFF, reset) | spectra median 0.975, strongest partial in the same 10.8 Hz bin in 91 % of windows, loudness envelopes correlate 0.991 |
| "Drooling", first 3 s, dump player + core vs the machine | spectra median **0.988** (10th percentile 0.955), strongest partial in the same bin **98.3 %**, loudness envelopes correlate **0.995**, level +1.8 dB median |
| A 120-frame excerpt looping back to frame 40, 4 s (the player's jump) | spectra 0.989, partials 96.2 %, envelopes 0.995 |
| ym-test end to end (50 MHz + 40 MHz, 4 frames) | every sample the HDMI sink hears is the core's, in order; 44.1 kHz; no FIFO fault |

Break tests (`ZM_RTL_BREAK=1`): 20 mutants of the PCM (gains, loop end, stop,
step, trigger, the mid-sample write rule), mix (clamp, floor), reset, YM clock,
frame rate, R13 rule, box filter, dump player (jump, wait) and FIFO, each caught.
The mid-sample test found a real bug on its first run (a SetActive written during
a sample also dropped that sample's step), fixed before this was written.

### The YM is not sample-exact, by design, and jt49 is the better YM

jt49 is a cycle-level model of the chip; `ym.zig` is a float model point-sampled
at 44.1 kHz. Tone edges land a sample apart, so the plain sample difference is
large (up to a full square, 10,813 LSB: both put a volume-15 channel at exactly
0.33 of full scale) while the music agrees. Where they differ, the evidence:

- **DAC curve.** Against Paulo Simoes's measurement of a real ST (Hatari,
  `ym2149_fixed_vol.h`, one channel, levels 1..15 relative to 15): jt49 is within
  **1.6 dB** at every level; `ym.zig`'s table is up to **7.8 dB too quiet** at
  low levels (-7.5 dB at volumes 2..4, -4.4 dB at 8). Hence the RTL's +1.8 dB.
- **Envelope shapes 11 and 15** (hold with alternate): the datasheet and Hatari
  (`YmEnvDef`: B = `\---`, F = `/___`) hold at the alternated level. jt49 does;
  `ym.zig` holds 11 at zero and 15 at the top: **a machine bug**, pinned by
  `test_the_envelope_holds_as_the_datasheet_says`.
- **Mixing.** Both sum the channels linearly; a real ST compresses (three channels
  at 15 are +5.5 dB over one, not +9.5). Neither models it.
- **Ultrasonic tones** (period 0..5): ym.zig gates them at 0.5; jt49's box filter
  gives the same mean with a small residual ripple (-35 dB).

**Decision:** keep jt49's DAC in the RTL (closest to the hardware), and fix the
machine instead: `ym.zig`'s envelope hold, and its DAC table to the measured ST
curve. Then the wasm machine and the FPGA agree with each other *and* with an ST.
That machine change moves every scene's audio, so it is its own task.

## 4. Costs (Yosys `synth_xilinx`, `make -C fpga util`)

| Block | LUT | FF | DSP | Notes |
|---|---|---|---|---|
| `zm_audio_ym` (jt49 + box filter) | 246 | 287 | 0 | jt49 alone: 286 / 291 |
| `zm_audio_pcm` | 639 | 354 | 1 | + 45 LUTRAM (the channel state) |
| `zm_audio_mix` | 127 | 35 | 1 | |
| `zm_audio_fifo` | 27 | 74 | 0 | + 6 LUTRAM |
| `zm_hdmi_acr` | 28 | 70 | 0 | |

| **`zm_audio_core`, whole** (native Yosys in the openXC7 container) | **1,270** | 720 | 2 | + 47 RAM32M; 7.2 % of the 7010's LUTs |

yowasp's Yosys (what `tools/util.py` runs) traps in ABC on the flattened core,
so `make util` lists it part by part; the whole figure is the container's.
The ym-test bitstream in all (core, dump player, FIFO, HDMI transmitter, test
pattern, serialisers): **1,777 LUTs, 1,454 FFs, 17 RAMB18 (the tune), 3 DSP48**;
openXC7 timing: sys 109.0 MHz (needs 50), pixel 123.8 MHz (needs 40), the 5x
serialiser clock 489 MHz (needs 200).

## 5. The board test: `make -C fpga ym-test`

`build/ym_test/ym_test_top.bit`: jt49 plays **"Drooling" by 505** (YM5 dump,
`docs/music/union/Drooling.ymraw`, 2:08, looped) from 22,678 ROM words in BRAM,
44.1 kHz over HDMI1 with the colour-bar test pattern. Load it as the other test
bitstreams: `openFPGALoader -c digilent_hs2 fpga/build/ym_test/ym_test_top.bit`.

What to hear: the same sound on both speakers (the YM is mono). The first ~4 s
are channel C alone, short melody notes around 350 Hz with rests; then the
envelope **buzzer bass** comes in on channel B (sawtooth/triangle envelope shapes
8/10/14, about 74-290 Hz), with channel A joining. PL_LED1 blinks at 1 Hz (it
toggles every 22,050 samples sent: the 44.1 kHz clock); lit steadily means a FIFO
fault. PL_LED2 is lit while the PLL is locked.

## 6. In the SoC (2026-10-09)

The board SoC (`soc/zm_z7.py`, unless `--no-audio`) has the sound: the core in
the system clock domain, HDMI with audio in place of DVI, the players in software
on the cart CPU (ADR 2026-10-09 "SNDH in software on the cart CPU").

```
cart CPU (firmware, M)                      fabric
  cart.frame()                                 
  song bridge (zg.requestSong / sndhCall)      
  demo-audio.wasm via wasm2c  --QA/QD-->  zm_audio_sched (2,048 stamped writes)
   (MOD, YM dump, SNDH=Musashi)               | each at its sample, between two mixes
   machine* -> stamped writes                zm_audio_core (jt49 + Paula + mix) <-- HP3: PCM bytes
                                              | 44.1 kHz, sys clock          (players' memory in DDR)
                                             zm_hdmi_out: FIFO -> pix -> zm_hdmi_tx -> ODDR -> HDMI1
```

**The register path.** The machine's audio ABI is calls (`machine/sdk/audio.zig`),
made by the open players in `demo-audio.wasm`. The firmware runs that module through
wasm2c (`fpga/cycles/audio.mk`; its imports renamed `env` -> `aud` by
`tools/wasm_env_rename.py`, so its 3 MiB memory stays apart from the cart's 7 MiB),
and serves its `machine*` imports (`fpga/host/audio_imports.c`): each call becomes the
core's register writes (`fpga/host/audio_regs.h`, the map of section 2), **stamped with
the sample it lands before** in the machine's own stream: the end of the last piece
the player rendered (`machineRenderYm/MixPaula(off, len)`), the block's start before
any. The firmware (`fpga/cycles/baudio.c`) pushes each as two stores to
`AUDIO_WINDOW` (0x9200_0000: QA = {stamp, address}, QD = data), and
`rtl/audio/zm_audio_sched.v` applies it when the core's sample counter reaches the
stamp, while no mix runs. So the chips see the machine's writes in program order,
each at the machine's sample, however the cart CPU's time is spread over the frame:
a 50 Hz replay and a 15 kHz digidrum alike. The window is outside every seal window:
only the firmware reaches it, as only the sealed audio module calls the chips in the
browser.

| Word | Register | |
|---|---|---|
| 0 | QA (W) | {stamp[21:0], core byte address[9:0]} of the next write |
| 1 | QD (W) | its data; pushes {QA, QD} (dropped and `overflow` set if full) |
| 2 | NOW (R) | samples started since reset |
| 3 | LEVEL (R) | writes queued |
| 4 | STATUS (R; W clears) | {core status[2:0], overflow, late} |
| 5 | PCM_BASE (RW) | bus address of the players' memory |
| 6 | APPLIED (R) | writes landed |
| 7 | ID (R) | 0x5A410100 |

**Pacing.** Each frame, after `cart.frame()` and the song bridge (the loader's
order), the players render up to NOW + 2,940 samples (67 ms). A song load (an SNDH:
depack, 1 MiB of 68000 RAM zeroed; a few Mcycles) re-anchors the stamp a full lead
ahead, so the tune starts on time (`anchors`). A frame longer than the lead makes the
stamp jump ahead (`resyncs`) and those writes land late (`late`). The counters are in
the debug mailbox for U-Boot: `md.l 0x05ffff80 8` = 'ZMAU', pushed, applied, status,
resyncs, anchors, now, level.

**PCM memory.** Where the machine keeps it: in the players' own wasm memory (the
song RAM at 0x200000 of it), here calloc'd in the firmware's heap in DDR. A Paula
DATA address is an offset in that memory; the core asks one byte at a time, and
`AudioHP` (`soc/zm_audio_soc.py`) reads it as one 1-beat 8-byte read on **HP3**
(PCM_BASE + offset masked to 4 MiB, mapped into the cart CPU's 32 MiB DDR window
like every HP master), about 25 clocks: four channels take ~100 of the 2,268 clocks
of a sample. No cache: the CPU's stores are write-through and acknowledged by DDR, so
a byte the players wrote is the byte read. Not BRAM: the song RAM is 1 MiB. The core
and the reader are held in reset while CTRL.RUN is low: no HP3 read can be cut by a
PL reload. Known limit: a PCM byte the players rewrite less than the lead before it is
played (an STE DMA double buffer) is heard new.

**HDMI.** `rtl/video/zm_hdmi_out.v`: `zm_audio_fifo` (sys -> pix), `zm_hdmi_tx` at
44.1 kHz (N 6272, CTS measured), the four TMDS lanes through `zm_oddr10` as
`zm_dvi_out` did. The sample rate on each side is an exact fraction of the one
crystal (`soc/zm_audio_soc.py rates()`: 441 / 1,000,000 of 100 MHz, the YM's 2 MHz
1 / 50), so the FIFO never drifts. The OSD still sits on the picture before it.

**Timing pass**: the PCM mix's multiplier operands are registered during FETCH
(`zm_audio_pcm.v`); the path `c -> channel LUTRAM -> min() -> DSP` failed 100 MHz by
54 ps. A VOLUME or PAN write now lands on the sample being mixed up to its FETCH
(the queue never writes during a mix). `pcm_exact` still passes; the PCM and queue
mutants still fail.

### Results

How it was checked, from the RTL up (`make -C fpga test`; the SoC runs with
`tools/audio_sim_run.py`, which builds the firmware, runs `host_audio` (the native host
with the machine's own chips, `fpga/host/audio_soft.c`) and the board SoC in Verilator
with a tap on the core (`rtl/sim/zm_audio_tap.v`), then `tools/audio_sim_compare.py`):

| Check | Result |
|---|---|
| `soc_stamped_exact`: the PCM script of section 3 as stamped writes through QA/QD, pushed ahead while the core runs | **13,466 samples identical** to the machine; every write landed at its stamp, between two mixes; none late or dropped |
| Queue mutants (`ZM_RTL_BREAK=1`): a write a sample early, a write during a mix, a write dropped | all 3 caught |
| tutorial (sos.sndh), 120 frames: the writes | **1,261 / 1,261** land at the machine's sample counted from the song's start, same values, same order |
| tutorial: the core's output vs the core on its own fed the machine's writes on the SoC's timeline (`tools/audio_core_replay.py`, the `core100` bench) | **148,010 / 148,010 samples bit for bit** |
| tutorial: the sound vs the machine's ym.zig (`ym`) | spectra 0.935 median, partials 68 %, envelopes do not correlate: see below |
| tsl_hybridglenz (a MOD), 40 frames | 87 / 87 writes; every sample within **25 LSB** (`near`): the MOD player's gains (v / 64 / 1.4, pan +-0.6) are off the VOL / 256, PAN / 128 grid and get rounded (`host/audio_regs.h`); on the grid the PCM is exact |
| Break: one YM R8 write dropped in the window (`hp_sim --audio-break drop`) | caught: 1,228 write differences |
| Break: the PCM base a byte off (`--audio-break base`) | caught: 21,675 samples off, worst 3,436 LSB |

**The YM against the machine.** The SoC adds nothing (the bit-exact replay), so what
differs is jt49 vs ym.zig, the question of section 3. On sos.sndh it is the envelope
(channel A on shape 10, period 42): jt49's output there depends on how long the chip
has run since its reset: replays of the same writes with different reset-to-song gaps
start the envelope at opposite ends (loud first vs silent first). The 60-frame run
matched the machine's shape, the 120-frame run did not. Open: whether jt49's envelope
restart (latched, applied on its 1/256 enable) loses the R13 write's phase; listen to
the bass envelope on the board.

**The cost on the cart CPU** (the board core, the DDR model, sys 100 MHz; the budget is
1.67 Mcycles a frame at 60 fps). The players alone (`make -C fpga audio-bench SONG=...`, `cycles/baudio_bench.c`: no
cart, the song started, then 735 samples rendered a frame, the writes pushed into the
real queue, run on the board SoC sim):

| Tune | Driver | Cycles a 60 Hz frame | Share of 1.67 Mc |
|---|---|---|---|
| sos.sndh (tutorial) | 50 Hz PLAY, no timer | 275 kc avg, 417 kc p95 (a PLAY ~315 kc) | 16.5 % |
| union/wow_scroller.sndh (union_superscroller) | timer A 7.6 kHz digidrum | 2,952 kc avg, 2,977 kc max | **177 %** |
| union/beat_dis.sndh (union_beatdis) | timer A 15.7 kHz digidrum | 7,948 kc avg (20 frames) | **477 %** |
| hybridglenz.mod (tsl_hybridglenz) | MOD (Paula is RTL) | 8 kc avg, 16 kc p95 | 0.5 % |

In the tutorial cart (sim, 120 frames): cart.frame() 466 kc, the music 364 kc avg, 588
kc p95, 669 kc max. A song load is a one-off 21-30 Mc (the 68000's 1 MiB zeroed, the
image depacked); the stamp re-anchors after it, so the tune starts on time. On the
board the tutorial runs 45.3 fps without music and 35.7 with (it was under 60 before:
the cart and the frame's waits). **A digidrum SNDH does not fit the cart CPU at 100
MHz**: every timer interrupt is a Musashi call (the replay's 68000 handler,
emulated). That is the audio CPU's job (ADR 2026-10-09).

**Timing and size** (Vivado 2026.1, `--sys-mhz 100 --comp-mhz 100`): met, WNS +0.139 ns,
WHS +0.024 ns. The SoC: 8,602 LUT (48.9 % of the 7010), 9,592 FF, 34.5 BRAM tiles,
10 DSP. `zm_audio_soc` 1,375 LUT, 900 FF, 9 RAMB18 (the queue), 4 DSP; `zm_hdmi_out`
597 LUT.

**On the board** (`build/soc_z7_audio`, tutorial with `ZM_BLIT=sw`): after 5 s the
mailbox read status 0, resyncs 0, the core at 44.1 kHz (223,809 samples in 5.07 s),
584 writes a second (sos.sndh: 12 a tick at 50 Hz). Heard: not yet.

```sh
# the bitstream (one heavy build at a time)
flock fpga/build/fable_timing3/.container.lock env PATH=/opt/vivado/2026.1/Vivado/bin:$PATH \
  LD_LIBRARY_PATH=$HOME/.local/lib/vivado-compat uv run python -m soc.zigmachine_soc --target z7 --build \
  --toolchain vivado --sys-mhz 100 --comp-mhz 100 --out build/soc_z7_audio        # from fpga/
make -C fpga board-fw CART=tutorial ZM_BLIT=sw                                     # no --blit in that bitstream
sg dialout -c "uv run --project fpga --with pyserial --with xmodem python fpga/tools/board_run.py \
  --bit fpga/build/soc_z7_audio/gateware/platform_z7.bit --fw fpga/build/hcycles/board/tutorial/fw.bin --secs 5"
# if its upload fails: the cart is stopped now, so upload by hand, then board_run again (crc matches)
sg dialout -c "uv run --project fpga --with xmodem --with pyserial python fpga/tools/uboot_loadx.py \
  fpga/build/hcycles/board/tutorial/fw.bin 0x04000000"
# the counters, from U-Boot: md.l 0x05ffff80 8  ('ZMAU' pushed applied status resyncs anchors now level)
```

## 7. Next: the sound-chip lab

Before choosing an extra chip for the console, build one **player bitstream per
chip**, the shape of ym-test: register dumps in BRAM, the chip core, the mixer,
HDMI at 44.1 kHz with the test pattern. Then compare their sound and their cost
(`tools/util.py`) on the real board, and decide. The winner goes into the wasm
machine first (the reference), then the SoC.

ym-test is the template, already split so that only the chip changes:
`zm_dump_player` (a ROM of `write reg, val` / `wait n frames` / `jump` words: any
chip with a register-write port), `snd_lab_out` (FIFO + HDMI + pattern), and a
converter to the ROM format (`tools/ym_rom.py` for the YM). A lab player swaps
`ym_test_audio` for its chip and writes its own converter.

| Candidate | Core | Dumps | Licence (to confirm per core) |
|---|---|---|---|
| SID 6581 / 8580 | MiSTer C64's SID, or the reDIP SID | register log recorded from `.sid` playback | GPL (MiSTer); check reDIP's |
| POKEY | MiSTer Atari800 | `.sap` register streams | GPL |
| YM2612 (FM) | jotego jt12 | `.vgm` | GPL-3 |
| OPL2 / OPL3 | jotego jtopl | `.vgm` | GPL-3 |
| NES APU | MiSTer NES | `.vgm` / `.nsf` register logs | GPL |
| SN76489 | jotego jt89 | `.vgm` | GPL-3 |
| Konami SCC | MiSTer MSX's SCC | `.vgm` | GPL |
| Game Boy DMG APU (2 pulse with sweep/duty, 32 x 4-bit wave, noise, per-channel pan) | MiSTer Gameboy (`gbc_snd`) | `.vgm` (DMG chip), `.gbs` register logs | GPL; about 500-1,000 LUTs (estimate) |

Most are GPL: each is a separate module, but a bitstream that holds one is a
combined work (as with jt49 today, `fpga/third_party/README.md`), to settle
before a bitstream is distributed. VGM-based chips share one converter: VGM's
`write` and `wait n samples` commands map onto the ROM words directly, at a finer
wait unit than the YM's 50 Hz frames.
