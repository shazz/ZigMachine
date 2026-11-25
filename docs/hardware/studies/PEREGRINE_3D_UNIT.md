# PEREGRINE 3D unit: the scenarios (R85)

Status: **brainstorm notes**, 24 Nov 2026 (Matt + lead session). Nothing is measured yet; every cost below is an
estimate. The scenario list itself is ROADMAP R85; this file keeps the comparison and the reasoning.

The model is the PS2: ZIGGY = the EE (game code), a "VU" = transform / clip / light / setup, CHISEL = the GS
(fill + texture). Matt's rules (23 Nov): no ARM / NEON in the render path (ASTROLABE stays a batch maths
coprocessor, "cheating" otherwise); every unit is optional behind the capability word (R41 B3), with the
software path as the fallback; KESTREL carts run unchanged on PEREGRINE; each unit needs a software model in the
machine wasm, since the gate runs carts in the browser / node.

## The five scenarios

| # | scenario | what | cost (est.) | sync / async | strength | weakness |
|---|---|---|---|---|---|---|
| S0 | software baseline | Q16 + ZM-X `mulsh` on ZIGGY (Kestrel Racing M1-M3) | 0 | sync | runs everywhere | every vertex costs ZIGGY |
| S1 | cheap ZIGGY additions (ZM-X) | dot3 / MAC Q16 on DSPs, 1/z estimate, min / max / clamp, packed SIMD 4x8 / 2x16 | hundreds of LUT | sync | small; wasm SIMD128 maps onto it | ZIGGY still does all the work |
| S2 | CHISEL as rasterizer ("the GS") | triangle / span setup; flat, Gouraud, affine / perspective texture spans | thousands of LUT | async (blitter queue) | fill rate is where texturing belongs | no help on transform |
| S3 | a VU core | BARD-like VexRiscv + ZM-X SIMD + DSP MACs + 16-32 KB BRAM scratchpad, descriptor queue (BARD-jobs plumbing), feeds S2 | ~3-6k LUT + BRAM | async (like VU1) | programmable: transform, clip, light, skinning, particles | a second CPU to program and sync |
| S4 | fixed-function T&L | hard-wired transform / clip / project / light, feeds S2 | ~2-4k LUT, 4-16 DSP | async | best throughput per LUT | rigid (PS1 GTE / GeForce 256, not the PS2 VU) |

Combinations: S1+S2 (cheap, broad) or S3+S2 (the real PS2 shape).

## S4 in detail: a pipeline, not a processor

No program counter, no instructions: stages that vertices stream through.

```
 cart (ZIGGY) writes a descriptor: matrix, light, vertex buffer, index list, output ring
        |
 [1 fetch]   DMA reads vertices from DDR (Q16 x,y,z + normal)
 [2 xform]   4x4 matrix x vertex: 12 MACs on DSP48s (3-4 DSPs time-shared, or 12 for 1 vertex a clock)
 [3 project] 1/z: reciprocal table + 1 Newton step, then x*f/z, y*f/z, viewport offset
 [4 clip]    outcodes; trivial accept / reject; the near-plane split (the only costly part)
 [5 cull]    2D cross product (backface), like the GTE's NCLIP
 [6 light]   N.L against 1-2 fixed lights -> a palette ramp index (flat shading)
 [7 key]     average z of the face -> sort bucket (the GTE's AVSZ3 / OTZ)
        |
 output ring: screen-space polygons + colour + depth key -> sort -> CHISEL fill (S2)
```

| | S3 (VU core) | S4 (fixed T&L) |
|---|---|---|
| what | a RISC-V with SIMD + scratchpad running a program | hard-wired stages, configured by registers / descriptors |
| speed | ~10-30 cycles a vertex (a program loop) | 1 vertex a clock pipelined (100 M vertices/s at 100 MHz): DDR fetch becomes the limit |
| cost (est.) | ~3-6k LUT + scratchpad BRAM | ~2-4k LUT + 4-16 DSP, little BRAM |
| flexibility | anything (skinning, particles, morphing, custom clip) | what was built in; a new effect = new RTL |
| software twin | runs the same RISC-V code: easy to keep equal | a C / Zig model of every stage, bit-exact vs the RTL |
| programming | microprograms (a second toolchain target) | fill a struct and kick it |

**The hard part of S4 is the near plane**: a clipped triangle makes new vertices, which breaks the one-in /
one-out stream. Hardware usually dodges it with a guard band (reject only polygons fully behind; the rasterizer
clips in screen space). CHISEL already clips to the screen, so a big guard band plus a near-plane "split or drop"
rule keeps S4 simple.

## S4-lite: GTE-style ZM-X instructions

The same stages as **synchronous ZIGGY instructions** instead of an async unit, like the PS1 GTE's `RTPT`
(transform 3 vertices), `NCLIP`, `AVSZ3`: the matrix lives in a few coprocessor registers, each instruction is a
handful of cycles. Maybe 1-2k LUT, reuses ZM-X's decode, maps easily in the wasm translator, and could even fit
KESTREL. Between S1 and S4: less speed than the async pipeline, but no queues and no sync model. A cheap stepping
stone to measure on the racer first.

## The trade-off and the lean (24 Nov)

- S4 is the console-designer choice: the most speed per LUT, but it bakes our renderer (flat-shaded, Q16, bucket
  sort) into silicon.
- S3 is the demoscener choice: the VU was loved because people did things Sony never planned.
- Lean for PEREGRINE: **S3**, with the GTE-style ZM-X instructions (S4-lite) as the cheap step measured first.
  Suggested order: S1 now (also helps KESTREL carts via SIMD), then S2 on PEREGRINE (texture spans in CHISEL),
  S3 only if the counters still show transform dominating after S1+S2.

## Fast and rigid vs 10-30x slower but programmable: the gap may not matter (24 Nov)

Per vertex S4 is ~10-30x faster than S3. At our polygon counts that gap mostly disappears (estimates): a frame is
~1.67 Mc at 100 MHz / 60 fps; take 3,000 vertices a frame (several times the racer oval):

| | cycles a vertex | 3,000 vertices | share of a frame |
|---|---|---|---|
| S0 (ZIGGY software) | ~150-250 | ~0.6 Mc | ~35 %, on the game CPU |
| S3 (VU core) | ~10-30 | ~30-90 k | ~2-5 %, in parallel |
| S4 (fixed T&L) | ~1 | ~3 k | ~0.2 %, in parallel |

- Both S3 and S4 take transform off the critical path. Once it is async and under ~5 % of a frame, the frame is
  set by **fill and sort** (S2's job), which neither touches. S4's extra speed pays only at tens of thousands of
  vertices a frame, and there CHISEL's fill rate and DDR bandwidth hit the wall first.
- **The gap shrinks if S3 is not a plain RISC-V**: a 4-lane Q16 MAC instruction on DSPs (matrix x vertex in 4
  instructions instead of 16 multiplies + adds: ~5-8 cycles a vertex), reciprocal and clamp as single instructions
  (shared with S1), two VU cores if LUTs allow. That is ~3-5x slower than S4, not 10-30x, and still programmable:
  essentially the real VU1 (a programmable core whose instructions are built around 4x4 matrix work).
- So the decision is not speed vs flexibility but **which bottleneck we buy for**. At "a few thousand polygons,
  flat or textured", S3 is fast enough and its flexibility (skinning, particles, morphing, demo effects) is free;
  S4 wins only at PS2-level polygon counts, where S2's fill rate is the real project.
- **Decide with data**: import the real Virtua Racing tracks (local only), read the racer's per-stage counters on
  KESTREL (vertex count, transform, collect, fill). Transform under ~20 % of the frame: S3, with S2 the priority.
  Transform dominating even with S1: S4 (or S4-lite) earns its rigidity.

## The yardstick

Kestrel Racing's per-stage counters (transform / sort / fill; R82). The oval no longer separates the scenarios:
it holds **60 fps with 8 cars on KESTREL** (board, 24 Nov). The yardsticks are the stress city (22 fps at R = 8:
collect 3.1 Mc + fill 1.6 Mc of the cart's 4.9 Mc) and the real Virtua Racing tracks once imported locally
(never committed). Fill being the second-biggest stage is why S2 likely pays first.

## Open questions for Matt

1. S3's shape: one VU, or two (a VU0-like sync macro mode + a VU1-like async unit, as on the PS2)?
2. S3's ISA: its own microcode, or RISC-V + ZM-X so the existing toolchain just works?
3. A study with OOC synth LUT numbers per scenario on the xc7z020 (Opus, after racer M4)?
