# BARD and the spare BRAM: a bigger cache or a scratchpad?

Study, 3 Nov 2026, branch `study/bard-bram`. Matt: "I was wondering if we can use the BRAM for a cache
or scratchpad (I guess way faster than accessing the DDR) for the BARD", "run studies for 1 and 2".

- **Option 1**: grow BARD's caches (D$ 4 KB → 8/16 KB, I$ 16 → 32 KB).
- **Option 2**: a tightly coupled data scratchpad (TCM) in BRAM at a fixed address, holding the hot tables.

**Recommendation: D$ 16 KB 2-way first** (+2.5 BRAM tiles, about +61 LUT). It is the only variant that
helps every player, and it helps the YM2612 candidate more than a 32 KB scratchpad costing three times
the BRAM. I$ 32 KB is the second step if Quartet must drop further (+4 tiles; both together fit the 10
free tiles). A scratchpad pays only for a core whose hot tables are rewritten to fit it (the Gens
ceiling below is -59 %), so it stays parked until such a core exists.

## The budget on the board

`board_combo9` (XC7Z010, the place report): 50 of 60 BRAM tiles, 15,670 of 17,600 LUT (89 %), 70 of 80
DSP. **10 BRAM tiles and ~1,900 LUT are free.** BARD today (same report): 1,611 LUT (I$ 505, D$ 355),
4 RAMB36 + 9 RAMB18 = 8.5 tiles, on the 100 MHz sys clock (sys WNS +0.049 ns).

## How it was measured

- `make snd-bench` (the players in demo-audio.wasm, 8 frames, no cart) and `make snd-cbench` (the Gens
  YM2612 core alone, 4 patches x 2 rates; GPL-2, kept in `prototypes/`, never committed), on
  `soc.hp_sim --sound-cpu` models with the sound core swapped: `--sound-core <netlist> --sound-tcm <bytes>`
  (this branch). Netlists from `vexgen/gen.sh`:
  `SndNd:16384:2:4096:1:snd,nodiv` (base), `SndNdD8:16384:2:8192:1:...`, `SndNdD16:16384:2:16384:2:...`,
  `SndNdI32:32768:2:4096:1:...`, `SndNdT:16384:2:4096:1:snd,nodiv,tcm`.
- Run on Matt's laptop (Verilator 5.052). Validation: Gens "worst" on the rebuilt base model,
  2.815 / 2.808 / 2.802 Mc for frames 0-2, against 2.814 / 2.808 / 2.802 from the 2 Nov run (0.03 %:
  the image now has `-fdata-sections`); Thalion 1.32 Mc against the documented 1.31.
- Numbers are the mean of the warm frames (frame 0 dropped), in Mc a 60 Hz frame and % of 1.67 Mc.
- The scratchpad core is the real thing, not a model: VexRiscv's `TightlyCoupledDataPort`
  (`vexgen/.../ZmTcm.scala`, a 256 KiB window at 0x9E000000 decoded in EXECUTE, data back in MEMORY)
  with a synchronous BRAM behind it (`soc/zm_sound_tcm.py`). A TCM access costs a D$ hit and never misses.
  Gens tables went into it with `-fdata-sections`, a linker script (`.bss.SIN_TAB` etc. into a NOLOAD
  `.tcm` section) and a calloc wrap for the chip struct: the core's source is untouched.

## The players

| Song (player) | base D4 | D8 | **D16 2-way** | I32 | best |
|---|---|---|---|---|---|
| dune_gen4_quartet #1 (native handler) | 1.621 (97 %) | 1.593 (96 %) | **1.495 (90 %)** | 1.478 (89 %) | I32 -9 %, D16 -8 % |
| thalion_forever (native, Hippel mix) | 1.321 (79 %) | 1.238 (74 %) | **1.069 (64 %)** | 1.274 (76 %) | D16 -19 % |
| beat_dis (native digi) | 0.695 (42 %) | 0.663 (40 %) | **0.656 (39 %)** | 0.692 (42 %) | D16 -6 % |
| wow_scroller (native digi) | 0.341 (20 %) | 0.335 (20 %) | **0.322 (19 %)** | 0.325 (20 %) | D16 -6 % |
| rings_of_medusa.hip (68000 + Paula) | 0.227 (14 %) | 0.203 (12 %) | **0.186 (11 %)** | 0.191 (11 %) | D16 -18 % |
| sos.sndh (Musashi) | 0.159 (10 %) | 0.147 (9 %) | **0.129 (8 %)** | 0.130 (8 %) | D16 -19 % |
| Warhawk.sap (6502 + POKEY) | 0.130 (8 %) | 0.128 (8 %) | **0.123 (7 %)** | 0.126 (8 %) | D16 -5 % |
| keygen_9000.xm (XM mixer) | 0.095 (6 %) | 0.092 (6 %) | **0.088 (5 %)** | 0.093 (6 %) | D16 -7 % |
| lollapalooza.mod | 0.002 | 0.002 | 0.002 | 0.002 | (hardware Paula: BARD only sequences) |

Bus waits behind them (k cycles a frame, I-bus / D-bus): Quartet 289 / 298 at base, 290 / 189 at D16,
179 / 271 at I32; Thalion 44 / 330 at base, 47 / 140 at D16. Quartet is split between both caches;
everything else waits on data. Every player already fits at base (Quartet at 97 % is the tightest);
only the Gens core is over.

## The YM2612 candidate (Gens core, snd-cbench)

| Case | base D4 | D8 | **D16** | TCM 32 KB: SIN_TAB | TCM 32 KB: chip | ceiling: TCM 256 KB (all) |
|---|---|---|---|---|---|---|
| worst, 44.1 kHz | 2.800 (168 %) | 2.433 (146 %) | **1.882 (113 %)** | 2.035 (122 %) | 2.368 (142 %) | 1.150 (69 %) |
| LFO on, 44.1 kHz | 3.422 (205 %) | 2.877 (173 %) | **2.298 (138 %)** | 2.617 (157 %) | 2.769 (166 %) | 1.546 (93 %) |
| alg 7, 44.1 kHz | 2.308 (139 %) | 2.094 (126 %) | **1.641 (99 %)** | 1.830 (110 %) | 2.001 (120 %) | 1.129 (68 %) |
| 3 channels, 44.1 kHz | 1.521 (91 %) | 1.307 (78 %) | **0.962 (58 %)** | 1.130 (68 %) | 1.202 (72 %) | 0.592 (36 %) |
| worst, 26.6 kHz | 1.720 (103 %) | 1.501 (90 %) | **1.152 (69 %)** | 1.250 (75 %) | 1.460 (88 %) | 0.693 (42 %) |
| LFO on, 26.6 kHz | 2.120 (127 %) | 1.799 (108 %) | **1.422 (85 %)** | 1.610 (97 %) | 1.727 (104 %) | 0.934 (56 %) |

- D-bus waits, worst at 44.1 kHz: 1,412 k (base), 1,137 k (D8), 725 k (D16), 844 k (SIN in TCM),
  912 k (chip in TCM), 37 k (ceiling). I$ 32 KB changes nothing (2.800). The TCM core with the base
  image (nothing placed) measures exactly the base: the port costs no cycles when unused.
- The tables are what Gens misses on: SIN_TAB 16 KB (pointer per phase), TL_TAB 96 KB (indexed by phase
  x envelope, scattered), the chip struct 18 KB; ENV_TAB 32 KB stays hot in the cache. Only one of
  SIN_TAB or the chip fits a 32 KB TCM, never TL_TAB.
- **The ceiling (-59 %, every case at 26.6 kHz under budget and 44.1 kHz worst at 69 %) is what a
  compact-table core could reach**: TL as int16 holding only its non-zero part (~7,200 entries, ~14 KB)
  and SIN as u16 offsets (8 KB) = ~22 KB, inside a 32 KB TCM. That is a rewrite of the core (and the
  licence question with it), not a hardware change.
- With D16 alone, Gens fits at 26.6 kHz (69 %, LFO 85 %) and is 13-38 % over at 44.1 kHz.

## Costs

| Variant | BRAM tiles | LUT | Source |
|---|---|---|---|
| D$ 8 KB 1-way | about +1 | ~+10 | data RAM x2, tag RAM one bit narrower (estimate) |
| **D$ 16 KB 2-way** | **+2.5** | **~+61** | ZIGGY's same DataCache 4 → 16 KB 2-way, OOC (ROADMAP, `feat/ziggy-dcache-zmx`) |
| I$ 32 KB 2-way | about +4 | ~+30 | sound_ooc: I16w2D4 2,353 LUT / 8.5 tiles → I32w2D16w2 2,387 / 15 |
| D$ 16 + I$ 32 | +6.5 | +34 | the same sound_ooc row (measured together), ~145 MHz routed OOC |
| TCM 16 KB | +4 | +60-100 (est.) | hit compare, one-hot data mux, a 32-bit stage register |
| TCM 32 KB | +8 | +60-100 (est.) | as above |

So D16 + TCM 32 KB (10.5 tiles) does not fit; D16 + TCM 16 KB (6.5) and D16 + I32 (6.5) do.

**Next step, not run (no Vivado on this box during the card build):**

```
cd fpga && uv run python tools/sound_ooc.py --core build/vexgen/VexRiscv_SndNdD16.v --out build/ooc_sound_d16
cd fpga && uv run python tools/sound_ooc.py --core build/vexgen/VexRiscv_SndNdT.v --tcm 32768 --out build/ooc_sound_tcm32
PERIOD=10 IMPL=1 uv run python tools/sound_ooc.py --core build/vexgen/VexRiscv_SndNdD16.v --out build/ooc_sound_d16_r
```

(`tools/vivado_ooc.sh` takes the Vivado lock itself.) Then the lead's bitstream: `SND_CORE` in
`cycles/sound.mk` / `SOUND_CORE` in `soc/zm_sound_cpu.py` pointed at `VexRiscv_SndNdD16.v`.

## Risks

- **Timing.** sys closed at +0.049 ns in combo9, and BARD's I$ / FPU paths were among the last misses
  (combo8). A 2-way D$ adds a way mux on the load path; the D16 OOC above must show BARD's block with
  margin at 100 MHz before it goes into the full build, and a full rebuild at 89 % LUT can miss for
  unrelated reasons. A TCM adds a 14-bit compare on the execute adder ahead of the BRAM enable;
  `tightlyCoupledAddressStage = true` registers it at one stall per TCM access.
- **Coherence (TCM).** The scratchpad is private to BARD: ZIGGY and CHORUS can never read it, so
  anything they share (PCM samples, the write queue, the mailbox, the scope mirror) stays in DDR. The
  D$ flush on a mailbox command does not touch it, so a song switch must re-stage its contents; it is
  zeros after a PL reload and keeps old data across BARD's reset. A bigger D$ has none of these issues
  (still write-through, flushed as today).
- **Placement (TCM).** The players are demo-audio.wasm through wasm2c: their tables and state live in the
  wasm linear memory (DDR, megabytes), so no Zig player table can move to a TCM without new wasm2c
  plumbing. Only C-side data can: the C stack, the w2c instance globals, or a native C core like Gens
  (a `.tcm` NOLOAD section filled at init, as done here; or a `.tcm.data` copied by crt like `.data`).
- **Measurement limits.** 8 frames a song from the start; two-variant combinations (D16 + I32) were
  not simmed together; LUT for D8/I32/TCM are estimates until the OOC runs.

## Files

- `fpga/vexgen/src/main/scala/zm/ZmTcm.scala`, `GenZm.scala` `--dTcm`, `gen.sh` flag `tcm`
- `fpga/soc/zm_sound_tcm.py`; `zm_sound_cpu.py`, `zm_audio_soc.py`, `hp_sim.py` (`--sound-core`,
  `--sound-tcm`); `tools/sound_ooc.py --tcm`; `cycles/sound.mk` `CBENCH_LDFLAGS`
- Local only (not committed): `prototypes/bard_bram_re/` (image scripts, linker scripts, `tcm_alloc.c`,
  `summary.py`, the UART logs in `out/`); the Gens core in `prototypes/gens2612_bench`, `prototypes/libvgm`.
