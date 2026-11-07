# SID on BARD: feasibility study (7 Nov 2026)

Matt: "can we build a soft version of the SID chip on BARD? ... let's give it a try". This is step 1, the
study. Nothing goes into the system image yet.

**Answer: yes for ordinary (PSID) tunes, no for RSID digi tunes, and not as cRSID ships.**

cRSID 1.58 (Hermit's light SID + 6502 player) is bit-exact on BARD: every frame's PCM hash equals the
host build's, on all six tunes. Its default engine costs **~2x BARD at 44.1 kHz**. Three levers bring
PSID tunes (1x and 4x, 6581 and 8580, filtered or not) to **48-60 % of BARD**, measured on the board's
sound core in the sim:
1. cRSID's **light engine**, not its default "HQ" engine (a runtime flag);
2. a **22.05 kHz** output, with cRSID's filter table regenerated for that rate (a data-only change made
   by cRSID's own generator);
3. **no soft divides** in the per-sample path. That takes a compiler flag (BARD's build makes GCC call
   `__divsi3` even for `x / 5`) and two small bit-exact patches to cRSID.

**RSID tunes** (real C64 programs: here the two digi tunes) cost **~1.8-2x BARD in any configuration.**
cRSID then emulates the 6502, both CIAs, the VIC and the envelopes on every C64 cycle, with no idle
shortcut between player calls. That 6502 + chip work alone is 2.4-3.2 Mc a frame.

On PSID tunes, the fixed floor before any SID voice is drawn is the 6502 and the envelope generators, at
~0.5 Mc (30 % of BARD). The envelopes cost twice the 6502.

## 1. Candidates

| Engine | Licence | Notes | Verdict |
|---|---|---|---|
| **cRSID 1.58** (Hermit, CSDb release 261057, March 2026) | "License is still WTF: Do what the frick you want with this code, but it would be nice mentioning me as the original author." (`README.txt`, `libcRSID/README.txt`, `libcRSID.c` line 2). No LICENSE file in the archive. | Integer-only C, a 6502 + CIA + VIC + SID machine, sample-paced. Two engines: "HQ" (cycle-based waves, 5x oversampled, the default) and "light" (all at the output rate). | **measured** |
| sidlite (libsidplayfp 3.x, `src/builders/sidlite-builder`) | GPL-2 (libsidplayfp's) | libsidplayfp's light engine, based on cRSID. Its output correlates 0.90 with ours (section 4). | GPL: reference only |
| reSID 0.16 / reSIDfp (libresidfp 1.2.3) | GPL-2 | Cycle-exact. An RP2040 at 300 MHz runs one SID. | too heavy; **the reference** (section 4) |
| TinySID and its forks | unclear | Lighter and much rougher (no combined waves, crude filter) | not pursued |

The licence is permissive but informal: it asks for attribution. A vendored copy should keep Hermit's
README and credit him in the about/credits text.

## 2. Setup

- `tools/sid_bard_fetch.sh`: cRSID 1.58 from CSDb and the six HVSC tunes, into `prototypes/sid_re/`
  (git-ignored: the tunes are never committed).
- `tools/sid_bard_bench.sh <tag> [host|bard|all] [cflags]`: the tunes as C arrays, then
  - the host twin (`tools/sid_bard_host.c`): the per-frame hashes and a WAV of each tune;
  - the BARD image (`make snd-cbench`, `cycles/sound/sidbench.c` + `cbdiv.c`).
- `tools/sid_bard_run.sh <tag>`: runs it on `soc.hp_sim --sound-cpu --sound-core
  VexRiscv_SndNdD16Dyn8Sx.v` (the combo16 board core, `vexgen/gen.sh
  SndNdD16Dyn8Sx:16384:2:16384:2:snd,nodiv,dynpred,h8,shex`) under the sim-b lock. `tools/sid_bard_check.py`
  then checks every frame's hash against the host's.
- **The unit is a 60 Hz frame**: 735 samples at 44.1 kHz, 367 at 22.05 kHz, against BARD's 1.667 Mc.
  "Mean" is the mean of frames 1-5, after frame 0 is dropped; "peak" is over frames 0-5. The tune's start
  (cRSID's init, plus the PSID INIT routine) is a one-off ~0.54 Mc.
- **The profile** is a local copy of cRSID (`prototypes/sid_re/scripts/mkprof.sh`). It reads BARD's cycle
  counter between the phases of `cRSID_emulateC64`. The buckets are:
  - **cpu**: the 1 MHz loop, which is 6502 + CIA + VIC + the three ADSRs per instruction;
  - **adsr**: split out of cpu in one run (two counter reads per 6502 instruction, +5 % overhead);
  - **wave**: the HQ engine's oversampled oscillators;
  - **filt**: the filter and output stage (in the light engine, the whole SID).
- The sims ran ~60-100 kHz on this box: 6 frames of a 3 Mc tune take ~6 min.

## 3. Measured on BARD

### The levers, one tune (Commando, Hubbard, 1x, 6581)

| Config | Mean Mc | % of BARD | Soft divides / frame | cpu | wave | filt |
|---|---|---|---|---|---|---|
| HQ (default), 44.1 kHz, stock | 3.31 | **199 %** | 2205 | 0.52 | 2.19 | 0.45 |
| light, 44.1 kHz, stock | 2.10 | 126 % | 1437 | 0.50 | 0.05 | 1.35 |
| light, 22.05 kHz, stock | 1.28 | 77 % | 718 | 0.47 | 0.03 | 0.68 |
| HQ, 44.1 kHz, `-mno-div` + patches | 2.63 | 158 % | 0 | 0.44 | 1.74 | 0.26 |
| light, 44.1 kHz, `-mno-div` | 1.70 | 102 % | 1437 | 0.43 | 0.01 | 1.09 |
| light, 44.1 kHz, `-mno-div` + patches | 1.21 | 73 % | 0 | 0.47 | 0.02 | 0.57 |
| light, 22.05 kHz, `-mno-div` | 1.07 | **64 %** | 718 | 0.40 | 0.01 | 0.55 |
| **light, 22.05 kHz, `-mno-div` + patches** | **0.83** | **50 %** | **0** | 0.42 | 0.01 | 0.28 |

With ADSR split out (the last row, +5 % for the probe): **6502 + CIA + VIC 0.19 Mc, ADSR 0.35 Mc**, SID
voices + filter 0.26 Mc.

**Where the time goes:**
- **Soft divides.** BARD has no divider, and one `__divsi3` costs **402 cycles** (1000 of them timed in
  the bench). cRSID divides per sample:
  - HQ: twice by the oversample count (5 or 6) and once by the attenuation (13) a sample. That is 2205
    divides, 0.89 Mc, or 53 % of BARD on their own.
  - light: once by the attenuation and once a pulse voice by its frequency step.
- **GCC 13 with `-march=rv32i_zmmul` calls `__divsi3` even for `x / 5`.** With `-march=rv32im -mno-div`
  it synthesises the divide with MULH, as it should. That is codegen only: the link keeps the rv32i
  multilib, and the image's DIV/REM guard still passes. This is BARD-wide (cycles/sound.mk `SND_ARCH`).
  The play image of 17 Oct has 61 `__(u)div/modsi3` call sites, of which ~8 have an immediate divisor.
  - Worth a separate, measured change of `SND_CFLAGS`. It does not touch the SID work.
- **The two patches** are bit-exact: the same hashes as stock on every tune, host and BARD.
  - `ZDIV(x, d)`: a runtime divide by a run-constant divisor (the oversample count, the attenuation)
    becomes a switch to constant divides, which `-mno-div` turns into multiplies.
  - `ZRECIP`: the light pulse's `PHASEACCU_MAX / PhaseAccuStep` is memoised per voice. The step only
    changes with the frequency register.
- **The ADSRs are the fixed floor.** cRSID clocks the three envelope generators after every 6502
  instruction, and after every 7-cycle idle step between player calls: ~2,300+ steps a frame, whatever
  the tune does. They cost 0.35 Mc (21 % of BARD), twice the 6502 itself.
  - Clocking them per output sample would be the next lever, but it changes cRSID's envelope timing,
    so it is not bit-exact.
- **The HQ engine's waves are 2.2 Mc** at a fixed ~246 kHz oversample rate, whatever the output rate. HQ
  does not fit BARD in any configuration measured.
- **Variance from code layout: ±8 %.** cRSID's `cRSID_emulateC64` inlines to 69 KB, and BARD's I$ is
  16 KB. Builds that only add the profile probes or `-mno-div` moved HQ by up to +18 % with no change
  in work (HQ: 199 / 211 / 217 %). The light builds are steadier.

### All six tunes, light engine at 22.05 kHz (filter curves regenerated for 22.05 kHz)

All builds are `-march=rv32im -mno-div`, light engine, 22.05 kHz, and every frame is bit-exact against
the host. The host replays the tunes BARD played before each one, because cRSID keeps state (filter
memories, the dither LFSR) across tunes.

| Tune | Kind | Stock cRSID: mean (peak) | Divides / frame | **Patched: mean (peak)** | Patched: cpu / SID Mc |
|---|---|---|---|---|---|
| Commando | PSID 1x, 6581 | 1.07 Mc, 64 % (66) | 718 | **0.83 Mc, 50 % (54)** | 0.47 / 0.28 |
| Cybernoid II | PSID 1x, 6581, filter | 1.36 Mc, 82 % (99) | 1058 | **1.00 Mc, 60 % (65)** | 0.61 / 0.30 |
| Club Style | PSID 1x, 8580, filter | 0.91 Mc, 55 % (56) | 367 | **0.80 Mc, 48 % (49)** | 0.53 / 0.20 |
| Wizball (sub 4) | PSID **4x** (CIA), 6581 | 1.17 Mc, 70 % (82) | 734 | **0.92 Mc, 55 % (73)** | 0.58 / 0.26 |
| Arkanoid | **RSID**, $D418 digi | 3.38 Mc, 203 % (229) | 367 | **3.31 Mc, 199 % (223)** | 2.80 / 0.39 |
| Storebror | **RSID**, NMI digi + filter | 3.04 Mc, 182 % (219) | 367 | **2.98 Mc, 179 % (224)** | 2.51 / 0.35 |

- **PSID mean: 53 % patched, 68 % stock** (`-mno-div` alone). Peaks are 49-73 %.
- **The tune start** is 0.36-0.53 Mc, one frame. Storebror's is 1.2 Mc: its init runs on the 6502.
- **RSID costs come from the cpu bucket:** 2.5-2.8 Mc of 6502 + CIA + VIC + ADSR. That is cRSID's
  RealSID mode: the C64 program runs on every C64 cycle, with both CIAs, the VIC and the IRQ/NMI lines
  emulated per instruction. The SID itself (0.35-0.39 Mc) is no dearer than on a PSID tune.
- D-bus waits a frame are 60-80 k on PSID, 540-680 k on RSID (the 64 KB C64 RAM plus the device state,
  against the 16 KB D$).

Tunes (HVSC, local only):
- Commando: Hubbard, 1x, 6581, no filter;
- Cybernoid II: Tel, 6581, filter in every frame;
- Club Style: Jammer, 8580, filter;
- Arkanoid: Galway, RSID, digi through $D418;
- Storebror: Mahoney, RSID, NMI digis + filter (the hardest kind of digi);
- Wizball: Galway, subtune 4, **4x speed** through CIA1.

### Memory

| | Code + tables | State |
|---|---|---|
| cRSID (`libcRSID.c.o`) | 154 KB (`cRSID_emulateC64` 69 KB inlined, `cRSID_emulateCPU` 30 KB, filter/waveform tables ~28 KB) | 276 KB (the C64's 64 KB RAM, I/O and ROM banks) |

Trivial against BARD's 2 MiB image and 3 MiB heap. The .sid file is copied into the C64's RAM.

## 4. Sound against the reference

The reference is sidplayfp 3.2.3 (libsidplayfp 3.1.2 + libresidfp 1.2.3, reSIDfp; GPL, built locally in
`prototypes/sid_re/ref/`, never committed): 20 s, mono, at 44.1 and 22.05 kHz.
`tools/sid_bard_compare.py` compares:
- the level (RMS);
- the 20 ms loudness envelope (its correlation at the best lag, which shows the same notes at the same
  time);
- the spectrum in octave bands.

A sample-exact comparison means nothing between two SID emulators: different filters, cRSID's dither
LFSR, and different start-up timing.

The candidate (light, 22.05 kHz, regenerated table) against reSIDfp at 22.05 kHz. Band columns are dB
against the reference, octave bands 63 Hz to 8 kHz:

| Tune | RMS dB ref / cRSID | Envelope corr. (lag) | 63 | 125 | 250 | 500 | 1k | 2k | 4k | 8k |
|---|---|---|---|---|---|---|---|---|---|---|
| Commando | -16.6 / -18.7 | 0.24 (1.5 s) | -3.2 | -1.2 | -0.7 | -0.5 | -0.5 | -0.4 | -0.4 | +1.3 |
| Cybernoid II | -22.2 / -20.3 | 0.75 | +0.7 | +0.9 | +2.1 | +3.9 | +3.7 | +3.5 | +2.2 | -0.8 |
| Club Style | -21.3 / -17.9 | 0.54 | +1.3 | +2.0 | +1.9 | +1.6 | +1.8 | +1.5 | +1.1 | +2.2 |
| Arkanoid | -12.3 / -14.6 | 0.86 | -1.3 | -1.4 | -3.1 | -3.3 | -3.8 | -4.5 | -4.9 | -4.1 |
| Storebror | -25.6 / -22.7 | 0.73 | +3.0 | +3.2 | +3.6 | +2.8 | +3.0 | +1.7 | +1.9 | +5.1 |
| Wizball | -19.3 / -15.8 | 0.86 (0.7 s) | -4.5 | -2.4 | +0.8 | +4.2 | +1.4 | +1.7 | +2.5 | +3.3 |

cRSID's own default (HQ, 44.1 kHz) against the 44.1 kHz reference gives the same picture: the same
correlations to within 0.04, and band levels within ~1 dB of the candidate's below 4 kHz. The light
engine and the lower rate cost little against the emulator-family difference.

- **Same music, same balance.** The band levels are within ~1-5 dB of reSIDfp on every tune.
  cRSID is a little louder on the filtered tunes (+2-3.5 dB RMS) and quieter on Commando and Arkanoid
  (-2 dB). These are emulator-family differences, not port errors: libsidplayfp's own cRSID-based
  `sidlite` engine gives the same Commando figures as ours (envelope correlation 0.90 with our render,
  band levels within 0.1 dB up to 2 kHz).
- **Commando's envelope correlation with reSIDfp is low (0.24)** for sidlite too. The two engines
  disagree on its envelopes (ADSR timing), and it carries no filter or digi to anchor them. Listen to it.
- **22.05 kHz needs the regenerated filter table.** With cRSID's stock 44.1 kHz table at 22.05 kHz,
  every cutoff doubles: Club Style's 125 Hz band went +6.6 dB against reSIDfp. With the table
  regenerated (cRSID's own `tools/curvegen.c` at 22050, a data-only change), it is +2.0 dB.
- **Digis play:** Arkanoid (0.86) and Storebror (0.73) correlate as well as the plain tunes.
- WAVs for Matt, in `prototypes/sid_re/wav/`:
  - `<tune>_ref.wav` and `_ref22050.wav`: reSIDfp;
  - `_hq44.wav`: cRSID's default;
  - `_lq44.wav`: light at 44.1 kHz;
  - `_xlq22.wav`: **the candidate**, light at 22.05 kHz with the regenerated table;
  - `_ulq22.wav`: the same with the stock table, to hear what the regeneration fixes;
  - `Commando_sidlite.wav`: libsidplayfp's sidlite.

## 5. What a player on BARD would take (step 2, not started)

The bar was "under ~70 % mean on BARD for 1x tunes". The candidate (light, 22.05 kHz, `-mno-div`,
patches) is under it on the BARD-native build, for PSID tunes. RSID tunes (digis, most modern demo
tunes) would need either the 6502/CIA loop made several times cheaper (cRSID's own design: cycle-paced
devices), or a refusal with a status word ("RSID: not on BARD"). A player should
check the header's magic and refuse RSID until then.

Before a player goes in, it needs Matt's decisions:
1. **Native C on BARD, not wasm2c.** The MP3 player went into demo-audio.wasm and costs ~1.3x its
   native build there (MP3 study, "The player as built"). 50-60 % x 1.3 is 65-80 %. That is over the
   bar beside a cart, so the SID player should be the native-path design the MP3 study sketched: C linked
   into snd.elf, bound to the player through a wrapped import. The browser needs a wasm build of the same
   C as its reference, so the hash-parity test is browser wasm against the BARD native build.
2. **The source is patched** (two bit-exact macros) plus a regenerated table, with Hermit credited.
   Without the patches, `-mno-div` alone gives 64 % on Commando (section 3).
3. **22.05 kHz mono output**, upsampled by CHORUS's Paula path (one PCM channel; the MP3 player's
   hi/lo trick is not needed for SID's dynamic range).
4. A demo tune: `libcRSID/tests/HerMiniSID.sid` (Hermit's own, 379 bytes, shipped inside the WTF
   library) is the redistributable candidate. No HVSC tune is committed.
5. Then, as the MP3 path did: a PLAYER_SID id (11, after PLAYER_MP3 = 10), a `requestSong` path for
   .sid, a harness named in build.sh with a break mutant, and an append-only system-table bump if the
   player needs a new import.

## Reproduce

```
tools/sid_bard_fetch.sh
FAST=1 CURVE_RATE=22050 tools/sid_bard_patch.sh       # the patched + probed copy, prototypes/sid_re/src_prof
P=$PWD/../prototypes/sid_re
SID_LIB=$P/src_prof SID_BARD_CFLAGS="-march=rv32im -mno-div" SID_WAVSEC=20 \
    tools/sid_bard_bench.sh xlq22 all "-DSID_PROF -include $P/src_prof/sidprof.h -DSID_HQ=0 -DSID_RATE=22050"
uv run python -m soc.hp_sim --sound-cpu --sound-core build/vexgen/VexRiscv_SndNdD16Dyn8Sx.v --out build/soc_hp_snd16
tools/sid_bard_run.sh xlq22                            # takes the sim-b lock
uv run --with numpy python tools/sid_bard_compare.py $P/wav/Commando_ref22050.wav $P/wav/Commando_xlq22.wav
```
Stock cRSID: leave out `SID_LIB` and the `-DSID_PROF -include` flags. One tune: `SID_LIST=<file>` (lines of
`<file.sid> <subtune> <note>`). The reference WAVs are sidplayfp's: `sidplayfp -f44100 -m -t20 -o<n> -w<out>`.
