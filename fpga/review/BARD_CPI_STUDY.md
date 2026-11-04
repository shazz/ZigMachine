# BARD's CPI: dynamic branch prediction and the other cheap VexRiscv options

Study, 4 Nov 2026, branch `study/bard-cpi`. Matt: "study then if good results implement". The klystrack
player's round 3 (`feat/kt-bard-3`) found BARD at ~1.7 cycles an instruction with bus waits only ~8 % of
the frame: the core (static prediction, MEMORY-stage branches) is the limit, not the memory.

**Result: the best cheap core is 1.21x on starport2's worst section and 1.16x on dpintro's, not the 1.25x
the brief asked for.** `SndNdD16Dyn8EbSx` (dynamic target predictor with a 256-entry BTB, branches in
EXECUTE, the shifter's result in EXECUTE) takes starport2 at 26 s from 2.691 to 2.231 Mc (161 → 134 % of
the budget: still over) and dpintro at 62 s from 1.813 to 1.563 Mc (109 → 94 %: **it fits**). Every
other player gains 6-13 %. Area and timing: see "OOC" below. The default (`SOUND_CORE` = SndNdD16) is
unchanged; the variants are selectable today with `--sound-core`.

## How it was measured

- Netlists from `vexgen/gen.sh` with the D$ 16 KB 2-way geometry of KESTREL v1.1
  (`16384:2:16384:2:snd,nodiv` + flags). New flags on this branch: `eb` (BranchPlugin `earlyBranch`),
  `shex` (FullBarrelShifterPlugin `earlyInjection`), `mulm` (ZmMulPlugin: MUL's low word written and
  bypassed from MEMORY). `dynpred` / `h8` were already there (TIMING_FABLE.md pass 3).
- Models: `soc.hp_sim --sound-cpu --sound-core <netlist>` on Matt's laptop (`~/cpi/zm`, this branch); the
  model's csr.json / hp_sim.json are byte-identical to the BRAM study's `bram_d16`, so its images are reused.
- Images (core-independent DDR images): the klystrack SNAP benches of round 3 (`make snd-bench SONG=x.kt
  SNAP=<frame>`: starport2 at frame 1560 = 26 s, dpintro at 3720 = 62 s, 6 frames each, built on
  `feat/kt-bard-3`) and the BRAM study's eight player images (8 frames from the song's start).
- Mean of the warm frames (frame 0 dropped), Mc a 60 Hz frame and % of 1.667 Mc. Waits = BARD's I-bus /
  D-bus wait counters (`FW` lines), k cycles a frame.
- Validation: the plain SndNdD16 model rebuilt from this branch gives starport2 2.691 Mc (round 3: 2.69),
  dpintro 1.813 (1.82), and the eight players to the third decimal of the BRAM study's D16 column.
- **Correctness**: every klystrack run ends with the SNAP checksum of the mixed output (`SUM`), and it equals
  the round-3 reference on all 20 KT runs (`sum-ok`): same samples, bit for bit, on every core. The player
  runs have no checksum; they all ran to completion (rc 0).

## The klystrack worst sections

| Core (vexgen flags after `snd,nodiv`) | starport2 @26 s | x | dpintro @62 s | x | waits I/D (starport2) |
|---|---|---|---|---|---|
| **SndNdD16** (static, the board's) | 2.691 (161 %) | 1.00 | 1.813 (109 %) | 1.00 | 53k / 251k |
| SndNdD16M (`mulm`) | 2.655 (159 %) | 1.01 | 1.781 (107 %) | 1.02 | 52k / 248k |
| SndNdD16Eb (`eb`) | 2.561 (154 %) | 1.05 | 1.757 (105 %) | 1.03 | 51k / 248k |
| SndNdD16Sx (`shex`) | 2.566 (154 %) | 1.05 | 1.701 (102 %) | 1.07 | 52k / 251k |
| SndNdD16Dyn8 (`dynpred,h8`: BTB 256) | 2.379 (143 %) | 1.13 | 1.702 (102 %) | 1.07 | 52k / 253k |
| SndNdD16Dyn (`dynpred`: BTB 1024) | 2.361 (142 %) | 1.14 | 1.688 (101 %) | 1.07 | 51k / 254k |
| SndNdD16Dyn8Eb | 2.347 (141 %) | 1.15 | 1.673 (100 %) | 1.08 | 51k / 254k |
| SndNdD16Dyn8Sx | 2.264 (136 %) | 1.19 | 1.593 (96 %) | 1.14 | 52k / 255k |
| **SndNdD16Dyn8EbSx** | **2.231 (134 %)** | **1.21** | **1.563 (94 %)** | **1.16** | 51k / 255k |
| SndNdD16DynEbSx (BTB 1024) | 2.220 (133 %) | 1.21 | 1.555 (93 %) | 1.17 | 51k / 255k |
| SndNdD16Dyn8EbSxM (+ `mulm`) | 2.201 (132 %) | 1.22 | 1.534 (92 %) | 1.18 | 52k / 255k |

- **The predictor is most of it** (1.13x / 1.07x), the early shifter the second lever (+5 %: the mixer
  shifts every sample and uses the result at once), early branch and `mulm` 1-2 % each.
- **A bigger BTB buys nothing**: 1024 entries against 256 is 0.5 %. The player's hot loops fit 256.
- **The waits do not move** (I ~52k, D ~250k a frame): every gain is pipeline stalls, as round 3 said.
  At 2.23 Mc, starport2 still spends ~1.9 Mc in the core. What is left is most likely load-use stalls
  (the D$ result comes back late in the pipeline) and the rest of MUL-use (`mulm` takes one of its two
  cycles); VexRiscv has no cheap knob for the first, and they were not measured one by one.

## The other players (Mc a frame, % of budget)

| Song (player) | SndNdD16 | Sx | Dyn8Sx | **Dyn8EbSx** | gain |
|---|---|---|---|---|---|
| dune_gen4_quartet #1 (native) | 1.495 (90 %) | 1.473 | 1.411 | **1.374 (82 %)** | -8 % |
| thalion_forever (native Hippel) | 1.069 (64 %) | 1.045 | 0.972 | **0.949 (57 %)** | -11 % |
| beat_dis (native digi) | 0.656 (39 %) | 0.648 | 0.596 | **0.582 (35 %)** | -11 % |
| wow_scroller (native digi) | 0.322 (19 %) | 0.316 | 0.291 | **0.284 (17 %)** | -12 % |
| rings_of_medusa.hip (68000 + Paula) | 0.186 (11 %) | 0.183 | 0.178 | **0.173 (10 %)** | -7 % |
| sos.sndh (Musashi) | 0.129 (8 %) | 0.128 | 0.123 | **0.121 (7 %)** | -6 % |
| Warhawk.sap (6502 + POKEY) | 0.123 (7 %) | 0.122 | 0.111 | **0.109 (7 %)** | -11 % |
| keygen_9000.xm (XM mixer) | 0.088 (5 %) | 0.086 | 0.079 | **0.081 (5 %)** | -8 % |

Quartet is bound by its I$ misses (290k wait cycles a frame on every core), so the core helps it least.

## OOC (Vivado, `tools/sound_ooc.py`, routed at 100 MHz)

`PERIOD=10 IMPL=1 uv run python tools/sound_ooc.py --core build/vexgen/VexRiscv_<core>.v --out build/ooc_cpi_<core>`:
the whole block (core, decoder, arbiter, posted bridge, registers), xc7z010-1, maxThreads 2.

<!-- ooc-table -->

## Recommendation

<!-- recommendation -->

## Files

- `fpga/vexgen/gen.sh` (flags `eb`, `shex`, `mulm`), `vexgen/src/main/scala/zm/GenZm.scala`
  (`--earlyBranch`, `--shiftEarly`, `--mulMem`), `ZmMulPlugin.scala` (`mulMem`, `zmx = false`).
- Laptop only (not committed): `~/cpi/` (`model.sh`, `run.sh`, `summary.sh`, the UART logs in `out/`).
