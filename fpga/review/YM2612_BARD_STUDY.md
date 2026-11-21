# YM2612 (Mega Drive FM) on BARD: results and the clean-room plan

Status (21 Nov 2026): **our own MIT core is built** (section 6: `libs/c/ym2612`, `libs/c/sn76489`,
`libs/c/vgm`, the .vgm player and VGM TEST, branch feat/ym2612-mit); board check pending.
Status (13 Nov 2026): **FM on BARD is validated on the board** with a local-only build of the Gens
YM2612 core. Matt, listening on KESTREL v1.3: "sounds great!!!!". That build stays **private**: Gens
(via libvgm) is GPL-2 and never enters this MIT repository. This document records what was proven, the
numbers, and the work for a shippable, clean-room MIT core.

## 1. What was built (local only)

Everything below lives in the git-ignored `prototypes/` tree on Matt's machine.

| part | where | what |
|---|---|---|
| player + core | `prototypes/gens_fm/player/` | VGM sequencer (`vgm.c`), SN76489 PSG (`psg.c`, our own code), the Gens YM2612 core (`fm_gens.c`, GPL), linear resampler (`resamp.h`), host player |
| BARD image | `prototypes/gens_fm/bard/` | `fm_bard.c` + `fm_out.c`: BARD's firmware, built through the `snd-cbench` path (`make board`, `make sim`) |
| cart | `prototypes/gens_fm/cart/` | `gens_fm.zig`: display-only scene (tune name, BARD load and peak); no Gens code, silent in the browser |
| reference | `prototypes/gens_fm/ref/` | libvgm's `vgm2wav` with the Gens core forced (`GENS_RATE`, `MUTE_PSG`, `MUTE_FM`) |
| tune | `prototypes/gens_fm/tune/ghz.vgm` | Sonic 1 "Green Hill Zone" (zophar.net Sonic 1 pack) |
| card | `prototypes/gens_fm_card/` | `CARTS/tests/demo-gens_fm.zmd` + `KESTREL/progs/by-hash/<hash>.rv32`, MD5SUMS |
| rebuild | `prototypes/gens_fm/REBUILD.sh`, `stage_card.sh` | the exact steps, in order |

Pipeline on BARD: VGM commands (0x52/0x53 YM2612 writes, every wait, 0x66 end + loop, the 0x67 type-0
DAC data block with 0xE0 seek and 0x8n) → Gens at **26,634 Hz** (the chip's native ~53.267 kHz / 2),
writes inside one chip sample collapse (last wins) → SN76489 mixed → linear resample to 44.1 kHz →
16-bit **stereo** on the four Paula channels with the MP3 player's hi/lo encoding (`x >> 1`, so half
amplitude) → CHORUS → HDMI. The VGM is linked into BARD's image (not streamed from the disk).

Not supported: data blocks after the first YM2612 one, Game Gear stereo (0x4F), chips other than the
YM2612 and SN76489. The PSG is point-sampled (a little aliasing at the top).

## 2. Results

**Fidelity (host, against libvgm's own player forced to the Gens core):**

| check | result |
|---|---|
| FM only, 44.1 kHz | correlation 0.99998, residual −43.6 dB, every band ±0.0 dB |
| FM only, 26.6 kHz + our resampler | correlation 0.991, flat to ~5 kHz, linear-interpolation roll-off above |
| PSG only vs libvgm's SN76496 | per-second loudness correlation 0.987, same pitches |
| RTL sim, CHORUS audio tap vs host | −75 to −78 dB |

**BARD load** (BARD = SndNdD16Dyn8Sx: I$/D$ 16 KB 2-way, dynamic branch prediction; KESTREL v1.3):

| where | rate | load |
|---|---|---|
| board, 13 Nov | 26,634 Hz | **66–74 % average**, cart meter peak 83.5 %, 60.5 fps, missed 0 |
| board OSD peak | 26,634 Hz | 114–117 % (one frame carrying a 256-sample render chunk; absorbed by the 4-frame output lead) |
| sim | 26,634 Hz | 63–73 % |
| sim | 44.1 kHz | ~107 % (over budget) |
| earlier bench (6 Nov, D$ 16 KB trial) | 26.6 / 44.1 kHz | 69 % / 113 % |

About a third of BARD's cycles in the render are D-bus waits (table lookups in DDR).

**Other cores measured earlier** (`BARD_BRAM_STUDY.md`, `BARD_CPI_STUDY.md`): ymfm (BSD, so licence-
compatible) is ~4× heavier than Gens: it does not fit. A compact-table rewrite of the Gens tables into
a 32 KB TCM reached 69 % at 44.1 kHz in the sim (a sim ceiling, not built for the board).

## 3. Why a clean-room core

Gens is GPL-2: it can run on Matt's board but cannot ship in the repo, the SDK or a public cart.
Mega Drive music in demos needs our own core. Clean room means: written from the hardware
documentation, never from Gens/MAME/Nuked source; Gens is used only as a black box to compare output
sample by sample.

## 4. The work (MIT YM2612 + VGM player)

1. **Spec from the hardware docs**, not from emulator source: the YM2612 register map, the operator
   pipeline (phase generator, envelope generator with its rate table, the log-sine and exponent
   ROM shapes, the 8 algorithms and feedback), LFO (AM/PM), timers A/B, channel 3 special mode,
   the DAC on channel 6, the 9-bit DAC output and ladder effect. Sources: the YM2612 / YM2608
   application manuals, the Sega Genesis technical overview, the documented hardware tests
   (SpritesMind threads by Nemesis and others) — cite each table's source in the spec.
2. **Fixed-point core in C** (BARD has no FPU and no divider: integer only, multiplies allowed),
   built for the BARD's caches: compact tables (sine quarter + exponent, ~2–4 KB) that stay in the
   16 KB D$, no per-sample divide, events stepped like `libs/c/ayumi` (envelopes advance per chip
   tick only when due). Target: ≤ 65 % of BARD at 26,634 Hz with DAC + PSG; 44.1 kHz as a stretch.
3. **Our own SN76489** (already written for the spike, our code: move it into the repo).
4. **VGM player streamed from disk** (`.vgm`/`.vgz`), the DAC data block in a BARD-side ring, loop
   support, a `zg.requestSong("x.vgm")` dispatch like the SNDH/SID players.
5. **Proof:** a harness comparing our core to recordings of the Gens reference (WAVs generated
   locally from libvgm, checked into nowhere; the harness keeps only error metrics and our core's
   hashes), per-feature unit tests (each algorithm, envelope rates, LFO, CSM, DAC), a `--break` per
   feature, all named in `build.sh`; then the board (`board_fps`, the OSD BARD load).
6. **Licence hygiene:** a short note per source file on where the knowledge came from; no Gens
   identifiers or table layouts copied.

## 5. Reproduce the private spike

`prototypes/gens_fm/REBUILD.sh` rebuilds the host player, the BARD image, the cart and the card;
`prototypes/gens_fm/bard/run_sim.sh` runs the BARD sim (take `prototypes/_gate_logs/sim-a.lock` or
`sim-b.lock`). The board install: copy the two files under `prototypes/gens_fm_card/`, restart glass,
pick tests → `gens_fm`.

## 6. The clean-room core: results (21 Nov 2026)

Built per section 4, all MIT and our own code: `libs/c/ym2612` (README: sources and the choices),
`libs/c/sn76489`, `libs/c/vgm` (sequencer, DAC streams, an inflate for .vgz, the output stage), the player
`libs/zig/players/vgm.zig` behind `zg.requestSong("x.vgm" | "x.vgz")` and `requestSongBytes(.vgm)`, the test
cart VGM TEST (139) with our own tune (`libs/c/vgm/make_tune.py`). Gate: `apps/vgm_check.mjs` (wasm =
native for the engine and the output stage, pinned feature hashes, refusals, malformed loops) with five
`--break`s, `apps/vgm_test_check.mjs`.

**Accuracy** (FM only, black-box, `libs/c/vgm/README.md`): Sonic 1's 19 tunes against Gens 0.891-0.996
(median 0.966) at the chip's rate and 0.862-0.991 (0.951) at 26.6 kHz; against Genesis Plus GX 0.950-0.998
(0.992) and 0.933-0.996 (0.982). Green Hill Zone: Gens 0.991 / 0.986, GPGX 0.996 / 0.993. Where Gens and the
other references disagree (the attack rate) the core follows the hardware notes.

**BARD load** (Verilator, the v1.3 core model `soc_hp_snd_dyn8sx`, 26,634 Hz with DAC + PSG, `snd-bench`
over the whole player, 6 frames; the tunes cut with `vgm_trim.py` to fit the bench image; "mean" is frames
1-5's cycles over 5 frames, a frame with two 256-sample engine refills is the peak):

| tune | operators computed a frame (`vgm_count`) | engine alone | whole player, mean / peak frame |
|---|---|---|---|
| Green Hill Zone from 10 s | 7,102 (whole tune: mean 7,761, max 8,880) | 57 % (before the EG cache) | **57.7 % / 64.8 %** |
| Special Stage from 10 s (all six FM channels, 24 operators) | 10,595 (tune mean 10,567) | - | **65.5 % / 73.0 %** |
| KESTREL FM (ours), from the start, before the C output stage | 4,526 | - | 57.7 % / 58.6 % |

The Gens spike on the same model: 63-73 % (board 66-74 %) on Green Hill Zone. Ours, over the whole of GHZ, is ~9 %
busier than the benched window (operators a frame), so ~62 % on average (estimated from the counts). The
load follows the live channels: the core skips released channels and operators at attenuation >= 832.
Two steps took the player from 77 % to 58 % on the GHZ window: the per-output-frame stage (resample + hi/lo
split) moved from wasm2c'd Zig into native C (`zm_vgm_out.c`), and the EG's update masks cached per operator.

**Not proven:** the board (glass's OSD fps / BARD load) and Matt's ear; the <= 65 % target holds for GHZ's mean
(57.7 %, ~62 % over the whole tune), Special Stage's mean is 65.5 %, and the busiest frames reach 64.8 % and
73 % (absorbed by the 4-frame output lead, as the spike's 114 % peaks were); SSG-EG (the references disagree with each other); a VGM over
983,040 bytes (refused, not streamed); the snd image's remaining room (2,044,112 of 2,097,152 bytes).
