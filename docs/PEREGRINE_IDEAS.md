# PEREGRINE: ideas for KESTREL's big brother

PEREGRINE is the next ZigMachine console: the same machine on a **Zynq 7020** (MicroPhase Z7 board,
ordered 14 Nov 2026, about six weeks away), named after the fastest falcon. Against the 7010:
~53,200 LUTs vs 17,600, 220 DSP vs 80, ~2.3x the block RAM, the same dual Cortex-A9.

**Nothing here is planned yet** (Matt, 14 Nov: "nothing to plan for now"). It is a list to grow
until the board arrives, ordered by what KESTREL suffered most from. Add ideas as they come, with
who/when and the KESTREL evidence behind them.

## 0. The rule: compatible first

- Every KESTREL cart runs unchanged on PEREGRINE. New capabilities are new system-table entries a
  cart can probe; a cart that uses them says so and falls back (or refuses cleanly) on KESTREL.
- The same tools, gate and SD card layout; one source tree, two board targets.

## 1. Room to breathe (the 7010's pain)

- **Timing margin before features.** KESTREL sits at 100 % slices; every feature fought timing
  (the last closures needed Fable). Spend the first LUTs on margin, then aim ZIGGY above 100 MHz
  (150 MHz?).
- **The FPU at full speed** with no clock-domain tricks, and **f64 in hardware on ZIGGY**: most
  of ASTROLABE's round trips go away (RAYTRACE's ASTROLABE mode was estimated slower than f32
  because of them).
- **A bigger ZIGGY RAM window** (128-256 MiB; KESTREL's 32 MiB is a parameter, see the ROADMAP
  row "ZIGGY RAM window 32 -> 64 MiB"): whole demos (Rift's 30 MB) load at once.
- Bigger caches (ZIGGY D$ beyond 16 KB, I$), now that block RAM is less tight.

## 2. 3D: where Suicide Barbie lost

The sb_spike measured why: the PSP lights and blends textured triangles for free, KESTREL doesn't.
- **CHISEL 3D**: perspective-correct spans, **Gouraud lighting**, **blended textured triangles**
  (additive, alpha, modulate).
- **A depth buffer** (no more precomputed draw orders, which Rift needed).
- **A triangle setup engine**: ZIGGY sends vertices, CHISEL walks edges and spans.
- **AFFINE / MAP onto true-colour planes** (missing on KESTREL: texturing falls back to the CPU).

## 3. Compositing (FRESCO)

- **8 planes instead of 4**, and the per-plane cost down.
- **Alpha on true-colour planes** (KESTREL's are opaque; only 8-bit planes blend).
- **Hardware sprites** (Amiga / Neo Geo style), so many moving objects stop costing a plane or a
  redraw each.
- **720p output** if the HDMI path allows, with clean scaling of the 320x200 / 640x200 / 640x480
  modes.

## 4. Sound and coprocessors

- **BARD with an FPU and a bigger D$** (the combo13 trial that did not fit), or **a second BARD**
  for jobs only (KESTREL gives a job ~100k cycles a turn between music renders).
- **The clean-room YM2612 in hardware** (FM with no CPU; the Gens spike proved FM on BARD), and
  SID / POKEY next to the YM.
- **A fast ZIGGY <-> ARM path** (ACP or on-chip shared memory): ASTROLABE from ~18 us a call to
  ~1 us, and glass serving big data (streamed demos) quickly.
- **A DSP56k-like coprocessor**: the Falcon nod.

## 5. The rest

- **Ethernet** if the board has it (ZIGNIC over a cable, not only Wi-Fi), **USB host** for real
  pads and keyboards.
- The boot work carries over: the fast boot (no phantom PHY stall), Wi-Fi at boot, the WINDHOVER
  splash, and a splash from U-Boot (the zeST study's option B).

## Log

- 14 Nov 2026 (Matt + Claude): first list; name PEREGRINE (GYRFALCON "too similar").
