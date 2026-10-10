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

## 6. Next: into the SoC

After the ODDR-serialiser and OSD work lands: `zm_hdmi_tx` (44.1 kHz parameters)
replaces `zm_dvi_out` in `soc/zigmachine_soc.py`, the pixel clock's audio side is
`snd_lab_out`'s FIFO + tx minus the test pattern, and `zm_audio_core`'s register
block goes on the cart CPU's bus inside the seal window (a Wishbone adapter:
`wr && ready` is its ack), with its PCM port on the memory path to the song RAM in
DDR (a byte fetch with a small line buffer; one sample period is 2,268 system
clocks at 100 MHz, the four channels need about 40). The machine's audio SDK
calls then become register writes, and the SNDH coprocessor (the plan's audio
CPU) drives the same registers.

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
