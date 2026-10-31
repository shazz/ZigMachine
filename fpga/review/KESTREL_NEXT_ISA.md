# KESTREL next ISA: what new effects an extension would unlock (design note, 2026-10-31)

Question (Matt): the previous study measured ISA extensions against today's shelf and found nothing,
and that is the wrong yardstick: the shelf is ports of 8 MHz 68000 demos, which of course do not need
more CPU. **What could KESTREL do that it cannot today**, thinking like a 1990s-2000s demoscener: which
effect classes are out of reach on ZIGGY now, and which instructions, coprocessor features or memory
changes bring each one to 60 fps?

Reconciliation with the prior work: `ZIGGY_ISA_EXTENSIONS.md` (worktree `agent-a65bf3ed2a2c1cea7/
fpga/review/`) stands for the shelf: build nothing for the existing carts; its `zm.p2c` is ST-port
headroom and is not re-argued here. `docs/RETRO_HW_FEATURES.md` (worktree `agent-a769379d7aadf0e92/`)
catalogued the era's hardware; this note takes its item 4 (the affine op) further and corrects one
item (the CHISEL command list exists: QUEUE, HW 1.8.0). Everything here is a **projection for content
that does not exist yet**; every cycle figure says where it comes from (the native bench, a GCC 13.2
compile of the loop, or an estimate).

## 0. The budget, and what ZIGGY is in era terms

- 60 fps = 1.667 Mc of sys clock. FRESCO takes 0.11 Mc a frame + 0.59 Mc an enabled plane (cost model
  fitted to the board, `docs/PERF_AUDIT.md` 2026-10-23). **One plane leaves the cart 0.97 Mc, two planes
  0.38 Mc**; at 30 fps with one plane, 2.63 Mc. The knee is a band, 1.75-2.1 Mc estimated.
- Per pixel, one plane at 60 fps: **15 cycles at 320x200** (64,000 px), **8.6 at 400x280** overscan
  (112,000 px); two planes: 5.9 cycles. That number decides every class below.
- Measured costs (`fpga/BENCH_REPORTS.md`, posted-store board): store 2.25 (any width: a word store
  is 0.56 c/px), D$ hit 1.74, D$ line miss 48, streaming read 7.2 a word, add 1.38, mul 3.16,
  div 36, f32 add/mul 9-10, f32 div 21, misaligned trap 213. Code at 1.01 cycles an instruction
  while it fits the I$. The ZIGGY D$ is **4 KB direct-mapped**: anything larger than 4 KB that is
  read at random (a texture, a height map, a distortion map) misses at 48 cycles a line.
- Era calibration: a single-issue in-order core at ~100 MIPS with a 10-cycle FPU is a **486DX4-100 to
  Pentium-75 class ALU on a 486-class memory system** (4 KB D$, ~48-cycle miss). The 1995-96 PC
  demoscene (Second Reality to Stars, Toasted, early Quake) at 320x200 is the honest target. The ALU
  is not the issue; the memory side is.
- **One fps rule for every estimate in this note**: with one plane, `fps ≈ 100 / (cart Mc + 0.70)`,
  capped at 60 (the recal table's board times are real averages, not VBL-quantised). "Today" and
  "after" figures below all use it, so the A/B of each showcase is comparable.

Instructions per pixel below were counted from GCC 13.2 `-O2 -march=rv32imf` output of the inner loops
written the way wasm2c's C comes out (the six loops and the command are in the appendix);
`_zba_zbb_zbs` changed fire 22 -> 20, tunnel 15 -> 14, nothing else, which confirms the prior study's
"B does not pay".

## 1. Effect classes: where they are bound, and what unlocks each

| class (320x200, 1 plane) | GCC instr/px or /item | est. cycles | Mc a frame today | fps today (rule above) | bound by | lever (section) -> Mc, fps after |
|---|---:|---:|---:|---|---|---|
| plasma, separable sine sum | 9 /px | 9 | 0.58 | 60 (78 uncapped) | ALU | packed add8 -> ~2.5 c/px, 0.16 Mc (1.3) |
| fire / blur / water (4-neighbour) | 22 /px | 22-24 | 1.4-1.5 | **47** | ALU | packed avg8/sub8s + funnel -> 5-6 c/px, 0.35 Mc, **60** (1.3) |
| shadebobs, additive particles, glow | 8 /px touched | 8 | ~0.5 | 60 | ALU | add8s: 4 px an op, ~0.15 Mc (1.3) |
| rotozoom, 64x64 texture (4 KB) | 14 /px | 14 | 0.9 | 60 (62 uncapped) | ALU | tex2d -> 9 c/px, 0.6 Mc; CHISEL AFFINE -> ~0 CPU (2) |
| rotozoom, 128x128 or 256x256 texture | 14 + misses | 25-35 | 1.6-2.2 | **34-43** | **D$ misses** | D$ 16 KB -> ~1.0 Mc, ~59 (1.1); + tex2d -> 0.7, 60; CHISEL AFFINE (2) |
| tunnel / any map-LUT effect (u16 map + 64 KB texture) | 13 + map stream + misses | 20-60 | 1.3-3.8 | **22-50** | memory | CHISEL MAP mode -> ~0 CPU (2); or texture <= D$ |
| voxel landscape, 320 columns x ~100 steps (Comanche) | 32 /step + misses | ~56 /step | ~2.0 | **37** | ALU + misses | D$ -> 1.2 Mc, 53 (1.1); + mulsh + tex2d -> ~26 /step, 0.83 Mc, **60** (1.2) |
| 3D transform, Q16, per vertex (3 rows + 2 divides) | 70 + 72 | ~150 | 10 k vertices: 1.5 | **45** | Q16 mul (5 instr) + div (36) | mulsh + rcp table -> ~50 /vertex, 0.5 Mc, **60** (1.2) |
| flat / Gouraud polys (fill) | CHISEL TRIANGLE ~1 c/px | +800 a call, or a QUEUE descriptor | 1,000 polys: 0.8 (calls) / ~0.1 (QUEUE) | 60 with QUEUE | call overhead | QUEUE exists (HW 1.8.0); AFFINE span op (2) |
| textured, perspective-correct spans (CPU) | 14 /px + 2 div a span | 18-25 | 1.2-1.6 | **43-53** | ALU | tex2d + rcp -> ~10 c/px, 0.65 Mc, 60; CHISEL span op -> ~0 CPU (2) |
| z-buffer | +5-6 /px | | +0.35 | | memory | don't: painter's sort (~0.1 Mc for 2,000 polys) |
| particles (update, erase, draw) | 25-30 /particle | | 30 k particles: 0.9 | 60 | stores | nothing needed |
| raymarching / SDF ray tracing | 12,000 /px (board, f32, `raytrace_f32`: 6,616 px/s at 80 MHz) | | 64 k px: **770** | 0.13 | everything | not an ISA question (1.4) |
| procedural textures (noise, 4K-intro style) | 100-200 /texel | | 64 KB texture: ~10 Mc **once** | init only | — | fine at init; per-frame passes use packed ops |

Three conclusions, which drive the ranking in section 4:

1. **The texture classes are memory-bound, not ALU-bound.** Rotozoom, tunnel, voxel and texture mapping
   all read a table bigger than 4 KB at random. No instruction fixes a 48-cycle miss; a bigger, 2-way
   D$ or a CHISEL op that owns the texture does.
2. **The 2D filter classes are ALU-bound at 22 instructions a pixel**, one byte at a time, because GCC
   has no 8-bit lanes on rv32. Four lanes of saturating add/sub/average give ~4x, and these are the
   effects the shelf has none of (fire, water, blur feedback, shadebobs: every 1993-96 PC demo had them).
3. **Fixed-point 3D is bound by two scalar ops**: a Q16 multiply is exactly this (GCC 13.2 does fuse
   the widening multiply, so the case for `mulsh` is the shift-and-merge, not the product):
   ```
   q16mul:  mul a5,a0,a1 ; mulh a0,a0,a1 ; srli a5,a5,16 ; slli a0,a0,16 ; or a0,a0,a5
   ```
   5 instructions, and a perspective divide is 36 cycles. One fused multiply-shift and a reciprocal
   table turn ~150 cycles a vertex into ~50.

### 1.1 Memory: the D$ (an instruction cannot do this)

`fpga/CYCLES.md` "Results: the caches" measured the netlists in the cycle sim: **I16w2D16w2 (D$ 16 KB,
2-way) is +67 LUT and +2.5 RAMB36 over the board's I16w2D4**, and 0 % faster on polkadots and skystrike,
which is why it was not taken. On the classes above the projection is different: a 128x128 texture
(16 KB) or a 128x128 height map stays resident, and 2-way kills the direct-mapped pathology where the
framebuffer row, the texture and a sine table alias at power-of-two strides whatever their total
size. Projected: rotozoom 256x256 from ~30 to ~16 c/px (the texture is still 64 KB; the wins are the
2-way set and the longer reuse), rotozoom 128x128 and voxel 128x128 nearly resident (the 16 KB table
shares the cache with the sine tables, the stack and the destination row: a handful of misses a row,
not one every few pixels). BRAM is the resource
KESTREL has (39 of 60 tiles used); LUT is not. **Caveats, both to measure before building**: the load
path gains a way-select mux (TIMING_FABLE.md's critical cone is fetch, but check the D$ path with an
OOC synth of the core), and the projection needs a synthetic rotozoom/voxel bench in the cycle sim on
both netlists, not today's carts.

### 1.2 Custom instructions, set 1: fixed-point maths (ALU-side, exact by construction)

All custom ops are R-type under `custom-0` (opcode 0x0B), `funct7` = op, `funct3` = variant, one
VexRiscv plugin (section 5). Semantics are given exactly so the browser twin is the same integers.

| op | semantics (exact) | latency | LUT (est.) | replaces | where it bites |
|---|---|---|---|---|---|
| `zm.mulsh rd, rs1, rs2` (funct3 0: >>16, 1: >>15) | `rd = bits[47:16]` (or `[46:15]`) of the signed 64-bit product `sext(rs1) * sext(rs2)`; arithmetic shift, truncating, no saturation | the MulPlugin's (3.16 dependent) | ~40: one more leg on MulPlugin's low/high result mux, **0 DSP** | 5 instructions (`mul, mulh, srli, slli, or`) | every Q16.16 multiply: matrices, DDA steps, Newton steps, voxel height scaling; Q15 on BARD |
| reciprocal | **no instruction**: a 256-entry Q16 table (512 B, D$-resident) + one Newton step = `lhu` + 2 `mulsh` + `sub` = ~8 cycles for ~16 bits, 2 steps for 24 | — | 0 | the 36-cycle `div` | perspective divide, voxel 1/z, span subdivision |
| `zm.tex2d rd, rs1(u), rs2(v)`; funct7 = (logW-3) in bits 0-2, (logH-3) in bits 3-5, W and H in 8..1024 | `rd = (((rs2 >> 16) & (H-1)) << logW) \| ((rs1 >> 16) & (W-1))`, logical shifts | 1 | ~80: two mask muxes + a shift mux selected by the immediate | 6 instructions (`srli, andi, srli, andi, slli, or`) | the texel address of rotozoom, tunnel, voxel, texture spans; also the Quake-style `shade[light][texel]` colormap (logW = 8) and any 2D LUT |

With both: rotozoom 14 -> 9 instructions a pixel; voxel 32 -> ~21 a step; a vertex transform ~150 ->
~50 cycles (3 rows of 3 `mulsh` + adds, 2 table reciprocals). A GTE-shaped coprocessor (RETRO item 6)
is not needed: 10,000 vertices a frame cost ~0.5 Mc with these two ops, and a transform engine would
be ~1,000 LUT + 9 DSP.

### 1.3 Custom instructions, set 2: packed 8-bit lanes (a P-lite, since P has no toolchain)

| op | semantics (exact, per byte lane i of 4, unsigned) | latency | LUT (est.) |
|---|---|---|---|
| `zm.add8s` | `rd.b[i] = min(rs1.b[i] + rs2.b[i], 255)` | 1 | ~50 |
| `zm.sub8s` | `rd.b[i] = max(rs1.b[i] - rs2.b[i], 0)` | 1 | ~50 |
| `zm.avg8` | `rd.b[i] = (rs1.b[i] + rs2.b[i]) >> 1` (**floor**: a round-up average never decays to 0, the classic fire bug) | 1 | ~50 |
| `zm.funnel rd, rs1, rs2` (funct3 k = 1..3) | `rd = (rs1 >> 8k) \| (rs2 << (32 - 8k))`: the word at byte offset k of the little-endian pair {rs2, rs1}, i.e. an unaligned word from two aligned loads | 1 | ~70 |

Fire at 4 pixels an iteration: 2 `lw` + 2 `funnel` for the x-1 / x+1 neighbours, 2 `lw` for the rows
below, 3 `avg8`, 1 `sub8s` (decay), 1 `sw` + loop ≈ 14 instructions a word, **~3.5 c/px against 22**;
400x280 fire drops from 2.5 Mc (31 fps) to ~0.4 Mc (60 fps with headroom). The same four ops cover
blur and water (avg8), shadebobs and glow (add8s), motion-blur feedback and cross-fades (avg8 of the
previous frame), bump-map normals (sub8s of heights), plasma (an 8-bit `add` without carry: use add8s
with values kept < 128, or add a non-saturating `zm.add8`, +30 LUT). Each op is a 4-lane adder with a
clamp: no DSP, no timing risk. Zbkb (accepted by GCC 13) is not a substitute: its `pack`/`packh`
assemble halves and bytes into a word, they do no lane arithmetic. A full P or a Zve32x vector unit
is out: no GCC 13 rv32 P (`-march=..._zpn` is refused), no VexRiscv vector plugin, 2-4 kLUT.

### 1.4 What stays out of reach, honestly

- **Raymarching / ray tracing at screen resolution**: 12 Kc a pixel measured; 60 fps needs 15. No
  instruction, FPU widening (the FPU already has `fsqrt`, `withSqrt = true`) or coprocessor that fits
  a 7010 closes a 500x gap. Keep it as the benchmark it is (`raytrace`, progressive).
- **Per-pixel perspective divide**: 36 cycles. Subdivide spans (every 8-16 px) with the reciprocal
  table, as Quake did; that is 1 c/px, not a hardware item.
- **True-colour per-pixel lighting**: FRESCO planes are 8-bit chunky with a palette each, by design;
  lighting is a palette ramp or a `shade[light][texel]` LUT (which `tex2d` addresses). That is the
  era's look. A direct-colour plane mode is not on the table (F3_ROW_ENCODING.md studied only the
  compositor's row encoding, not a cart-facing plane format).

## 2. Where a coprocessor or FRESCO/CHISEL feature beats an instruction

The role split that keeps the machine clean: **ZIGGY computes per vertex / per span / per particle;
CHISEL does per pixel where the pixel is a read-modify-write of memory; FRESCO does per line.** An
instruction wins when the loop is already running on the CPU and the memory is in the D$; a CHISEL op
wins when the inner loop is memory-bound (random texels) or the CPU has something else to do.

| need | instruction | CHISEL / FRESCO | verdict |
|---|---|---|---|
| rotozoom, Mode 7 floor, Lynx/Neo Geo scaling, quads | tex2d: 14 -> 9 c/px, still 0.6 Mc at 320x200 | **AFFINE op** (prior study: 300-500 LUT, 0-1 BRAM): ~1.5 c/px of CHISEL time, overlapped; texture reads leave the D$ entirely | CHISEL |
| textured polygons, thousands a frame | CPU spans ~10 c/px with set 1: 64 k px = 0.6 Mc + setup | the AFFINE op **taking a span list, not a row table**: per span `(x0, x1, y, u0, v0, du, dv)` (the prior spec's fixed-width `(u0, v0, du, dv)` row table only does floors). The CPU scan-converts: 2 table reciprocals a row for perspective-correct edges (~20 cycles), writes a descriptor per span (~8 stores, ~20 cycles); CHISEL walks it at ~1.5 c/px. Estimate: 2,000 small polys x ~10 rows x ~40 cycles = **0.8 Mc CPU + 0.1 Mc CHISEL overlapped**, so ~1,500-2,500 textured polys at 60 fps with one plane | CHISEL, **amend the op to spans** |
| tunnel and every map-driven effect | none (memory-bound) | **MAP mode** (`texel = tex[(map[i] + off) & mask]`, +100-150 LUT) | CHISEL |
| per-op overhead for many small ops | — | **QUEUE exists** (HW 1.8.0, `COMMAND` 5, descriptor list from a 512-word ring, CHISEL runs it from its own copy while the cart goes on). Per descriptor: the tap->op copy is 24 clocks a kick, ops still drain between descriptors; the CPU's cost is the descriptor stores (~20 cycles). **Unmeasured on the board: add `ch.q.fill8.x64` to the bench** before quoting a poly count | done; measure |
| fire / blur / shadebobs | **packed ops**: 4 px a cycle, the buffer is the CPU's | a CHISEL "filter" op would be a fifth sequencer for one effect; the data is already in the D$ | instruction |
| vertical stretch, reflections, line repeat, mosaic, sprite bands | nothing (a copy a line) | **per-line `FB_BASE` / LBASE in the copper list** (RETRO item 1, "soon"): 0 CPU, a list entry a line | FRESCO |
| global rasters without a handler | — | `BACKGROUND` in the global list (RETRO item 1; swedish_newyear's 0.46 Mc) | FRESCO |
| 3D transforms | mulsh + rcp table: ~50 c/vertex | a GTE: ~1,000 LUT, 9 DSP | instruction |
| collision, mirror, raw IFE/EFE | — | CHISEL small-ops bundle with the fold (RETRO item 3) | CHISEL |

DDR side of the AFFINE op: random texel reads cost the same ~48-cycle latency to CHISEL, but
`zm_blit_px` keeps 2^5 reads in flight, so independent texel addresses pipeline to ~1-3 clocks a
pixel; a 64x64 texture BRAM (+1 RAMB36) only if the board shows worse. BRAM is available.

## 3. BARD: real-time synthesis

BARD is RV32I + Zmmul (`mul`/`mulh`, no divider), 4 KB D$, 735 samples a frame at 44.1 kHz: **2,270
cycles a sample** for the whole frame budget. Costed from the same instruction counting (Q15 with
`mul + mulh + shift` = 5 instructions a multiply), misses included where the data leaves the D$:

| stage | per sample | 8 voices / full | Mc a frame | % of BARD |
|---|---:|---:|---:|---:|
| FM 2-op voice (phase adds, 2 sine lookups, 1 mul, envelope) | ~22 | 8 voices 176 | 0.13 | 8 % |
| subtractive: biquad or Chamberlin SVF (5 mul, 4 add, state) | ~35 | 8 filters 280 | 0.2 | 12 % |
| Freeverb-class reverb (8 comb + 4 allpass, stereo: 24 lines, ~40 KB, sequential) | ~200 + ~70 miss | | ~0.2 | 12 % |
| wavetable / sample voices (step, lerp, volume) | ~18 | 8 voices 144 | 0.1 | 6 % |
| **total synth, 8 FM + 8 filters + reverb + mix** | | ~660 | **~0.6** | **~35 %** |

So **a software synth already fits BARD**; nothing in it needs an instruction. BARD's real wall is the
68000 emulation: digi SNDHs run at 75-117 % and wow_scroller at 130 % (`docs/FPGA_SOUND_CPU.md`), bus
calls and I$ misses, not maths. A synth is an **alternative load** (a 64K-intro soundtrack instead of
an SNDH), not an addition on top of one. If BARD later gets instructions, they are the same plugin as
ZIGGY's in the `SndNd` netlist: `zm.mulsh` (funct3 1, Q15: 5 -> 1 instruction, ~25 % of the synth) and
`zm.add16s` (two saturating 16-bit lanes, a stereo sample add, ~40 LUT). ~80 LUT total, last in the
ranking: write the synth first and measure it with `make snd-bench`.

## 4. Ranked, LUT-aware proposal

Baseline: **~89 %, ~15,660 LUT** (the F3 decision of 2026-10-24; PERFORMANCE_REVIEW's 14,888 and the
posted-store 15,045 are older builds), 39/60 RAMB36, 32/80 DSP. Free LUTs exist on paper (~1,900) but
routing congestion above 80 % is what breaks 100 MHz, so every M-class item pairs with a cut. The
realistic cut pool: CHISEL sequencer fold **500-850** (SOC_REVIEW F5, high timing risk, to be built
with the AFFINE op as one new edge walker, not a fifth sequencer), blitter DSP/address pruning ~150,
interconnect decode ~200: **850-1,200**. jt49 is not in the pool (SOC_REVIEW F8: already folded to 233).
BRAM and DSP are the non-scarce resources: fund caches and texture buffers with them.

| step | what | LUT | BRAM | pay with | unlocks | showcase (A/B: est. today -> after; measure with the board OSD fps and `frame_cost --budget`) |
|---|---|---:|---:|---|---|---|
| 0 | **software first**: ZigOS `fx3d_fixed` (Q16 pipeline, reciprocal table, painter's sort), a span texture-mapper, `fx.fire/blur/shade` row routines. These ARE the browser twins of steps 2-3 | 0 | 0 | — | the content exists before the hardware does; the twins' tests | `texmap`: 1,000-poly textured torus, software spans: 1.2-1.6 Mc, **43-53 fps** (the step-3 A). `fxrows`: 320x200 fire + blur in the row routines: 1.4-1.5 Mc, **47 fps** (the step-2 A, and the packed ops' twin) |
| 1 | **ZIGGY D$ 16 KB 2-way** (`I16w2D16w2`, measured +67 LUT / +2.5 RAMB36) | +67 | +2.5 | nothing, if the OOC synth holds fmax | texture / height-map classes; every cart's aliasing | `roto128`: 128x128 rotozoom 320x200: 1.6-2.2 Mc (**34-43 fps**) -> ~1.0 Mc (**~59**; 60 with step 2). `voxel`: 320 columns: ~2.0 Mc (**37**) -> ~1.2 Mc (**53**; 60 with step 2) |
| 2 | **ZM-X v1**, one plugin: `mulsh` x2, `tex2d`, `funnel`, `add8s`, `sub8s`, `avg8` (+ `add8`) | ~400 | 0 | DSP pruning 150 + interconnect 200 (or part of the fold) | 2D filter classes at full res; fixed-point 3D at 10 k vertices | `inferno`: 400x280 fire + shadebobs + blur feedback: 2.5 Mc (**31 fps**) -> ~0.5 Mc (**60**). `morph10k`: 10 k-vertex dot morph: 1.5 Mc (**45**) -> 0.5 Mc (**60**). `voxel` from step 1 reaches 60 |
| 3 | **CHISEL AFFINE/SPAN op + MAP mode** on the folded edge walker, span-list descriptors through the QUEUE | +400-650 net of nothing; **~0 to -400 with the fold** | +1 (texture BRAM, if needed) | the CHISEL fold (500-850) | Mode 7 + per-line matrix, textured polys in the thousands, tunnels, scaling sprites, quads | `texmap` at **2,000 polys** (0.8 Mc CPU, **60 fps**); Mode 7 racer, 2 planes (road + sprites): CPU ~0.1 Mc, **60**; tunnel + roto overlaid, 2 planes (today 1.3-3.8 Mc one plane, **22-50**): **60** |
| 4 | **BARD ZM-X**: `mulsh` (Q15) + `add16s` | ~80 | 0 | leftover from 3 | cheaper synth voices (not a new class) | `synthdemo`: 8 FM voices + filters + reverb, no SNDH: BARD ~35 % -> ~25 % (`make snd-bench`, the OSD). `wavedemo`: 16 wavetable voices + reverb, 8 FM voices mixed in: ~55 % -> ~40 %; one step only needs two because it adds no class |

Net if everything lands: +67 +400 +(400..650) +80 ≈ +950-1,200 against a pool of 850-1,200: **the SoC
ends where it is, ~89 %**, with a different machine inside. Order matters: 0 costs nothing and is
needed anyway; 1 is cheap and funded by BRAM; 2 and 3 are the two real spends and each has a cut named.

Not recommended, and why:

| item | why not |
|---|---|
| Zba / Zbb / Zbs | measured here too: 22 -> 20 on fire, 0 elsewhere; `tex2d` and `funnel` do what the new loops need. Zba (~50 LUT) only if a cut leaves room, since GCC emits it for free |
| C (compressed) | 250-350 LUT on the fetch cone (the critical one); no cart near the I$; the new effect loops are small |
| Zicond | GCC 13.2 accepts `_zicond` but does not emit it (GCC 14); mispredicts are not the bound anywhere above |
| Zfh | wasm has no f16; GCC accepts `_zfh` for nothing |
| Zve32x / Zve32f, full P | no VexRiscv unit, 2-4 kLUT, `_zpn` refused by GCC 13; the P-lite above is the part that pays |
| a reciprocal / divide-step instruction | a 512 B table + `mulsh` Newton is ~8 cycles; the instruction would save ~4 |
| a GTE / matrix coprocessor | ~1,000 LUT + 9 DSP for what `mulsh` + the table do at ~50 c/vertex |
| z-buffer in CHISEL or FRESCO | DDR traffic for a look the era did not have; painter's sort |
| a CHISEL filter op (fire/blur) | the buffer is in the D$ already; a packed op is 4 px a cycle with no call overhead |
| `zm.p2c` | ST-port headroom (prior study); real users, but it unlocks no new class |

## 5. Toolchain path (verified this session with GCC 13.2.0 / binutils 2.42, `fpga/cycles/cycles.mk` flags)

- **Custom opcodes assemble today**: `.insn r CUSTOM_0, funct3, funct7, rd, rs1, rs2` produced
  `0x02b5050b` for funct3 0 / funct7 1 with no toolchain change. GCC accepts `-march=rv32imf_zba_zbb_zbs`,
  `_zicond`, `_zfh`, `_zve32x`, `_zbkb`, `rv32imfc`; refuses `_zpn`. It emits Zb* instructions from
  wasm2c's C (counted above), emits nothing for Zicond, and has no path to packed or vector ops on
  rv32, so **every op in sections 1.2-1.3 is an intrinsic, never codegen**.
- **How a cart reaches an op** (the prior study's two shapes, kept): the cart declares a wasm import,
  `extern "env" fn zmMulsh(a: i32, b: i32) i32`; wasm2c emits `w2c_env_zmMulsh(env, a, b)`;
  `fpga/cycles/zm_variant.h` (already spliced into every wasm2c output) adds
  `#define w2c_env_zmMulsh(e, a, b) zm_mulsh(a, b)` to a `static inline` with a **non-volatile** asm
  (`"=r"` output, `"r"` inputs, no memory clobber), so GCC can CSE and hoist it like an ALU op. ZigOS
  wraps each one (`zg.fx.mul`, `zg.fx.tex2d`, ...) so a cart never writes the import itself; the
  fixed-point library routes its existing `(a * b) >> 16` through `fx.mul`, which is how today's
  carts would gain without a source change.
- **Granularity**: `mulsh`, `tex2d`, `funnel` are **per-op intrinsics** (a cart's own inner loop needs
  them). The packed filters are better exposed **span-granular** too (`zg.fx.fireRow(dst, src, w)`,
  `blurRow`, `addRow`, `avgRow`): on the board a C loop with the instructions, in the browser a Zig row
  loop in rom.wasm, one call a row. A per-pixel import costs a wasm-to-wasm call in the browser
  (cheap, ~ns, but 64 k a frame is ~0.3-1 ms); a row import costs 200.
- **The twin**: the browser and node implement every import in rom.wasm (Zig), the native host and
  the sim in `zm_cart_rt` (C, the same expression, compiled without the instruction). Pixels match
  by construction because every op is integer-exact as written in 1.2-1.3; the tests that pin it are
  (a) a Zig unit test per op, exhaustive over the byte lanes / shift variants, run against the C twin
  and against the RTL testbench's vectors, (b) a `blitter_tb`-style testbench for the plugin,
  (c) an `hp_sim` run of each showcase cart hashed against `scene_hash.mjs`. Every new import joins
  `disk_check.mjs`'s `hostEnv` list (the rule in memory: a cart import the host lacks is a link
  error on the board and a silent miss in the browser).
- **The core**: one `ZmXPlugin` beside `fpga/vexgen/src/main/scala/zm/ZmSealPlugin.scala`, in the
  `SimdAddPlugin` style (decode mask on custom-0, result in the execute stage, bypassed like the ALU)
  for the 1-cycle ops; `mulsh` as a third select on `MulPlugin`'s result; `CfuPlugin` (present in
  the submodule) only if a multi-cycle op ever appears. A `zmx` flag in `vexgen/gen.sh`, two
  netlists (`I16w2D16w2SealFpuZmx`, `SndNdZmx`), an OOC synth of each for the LUT delta and the
  execute -> writeback slack before any bitstream. The sim's Verilated SoC must be rebuilt with the
  new core before `hp_sim` can run a showcase.
- **Firmware**: the ROM/system image is `-march=rv32imf`; the intrinsics live in the cart C only, so
  a cart built with ZM-X refuses to run on an old bitstream (it would trap on an illegal instruction):
  version the bitstream's ID register and have `zm_cart_rt` check it at boot, the way `csr.json` is
  checked today.

## Summary

Today's shelf needs nothing; the 1995 PC demoscene at 320x200, 60 fps needs four things in this
order: software libraries that are also the twins (0 LUT), a 16 KB 2-way D$ funded by BRAM
(+67 LUT), a seven-op integer plugin (~400 LUT: Q16 multiply-shift, 2D texel address, funnel shift,
four packed-byte ops), and the CHISEL affine op amended to take **span lists**, landed with the
sequencer fold so it is LUT-neutral. Each step has a showcase that runs under 60 fps today and
reaches it after. BARD's synth needs no hardware. Raymarching stays a benchmark.

## Appendix: reproduce the instruction counts

```sh
riscv64-unknown-elf-gcc -O2 -march=rv32imf -mabi=ilp32f -S loops.c -o rv32imf.s            # GCC 13.2.0
riscv64-unknown-elf-gcc -O2 -march=rv32imf_zba_zbb_zbs -mabi=ilp32f -S loops.c -o zb.s
awk '/^[a-z_0-9]+:/{f=$1} /^\t[a-z]/{c[f]++} END{for(k in c) print k, c[k]}' rv32imf.s     # instructions a function
printf 'int f(int a,int b){int r; __asm__(".insn r CUSTOM_0, 0, 1, %%0, %%1, %%2" : "=r"(r) : "r"(a), "r"(b)); return r;}\n' > insn.c
riscv64-unknown-elf-gcc -O2 -march=rv32imf -mabi=ilp32f -c insn.c && riscv64-unknown-elf-objdump -d insn.o   # 02b5050b
```

Counts (whole function, loop prologue included; the per-pixel figures in section 1 subtract it):
fire 22 / 20 (Zb), plasma 9 / 9, q16mul 6 / 6, roto 16 / 16, tunnel 15 / 14, voxel 32 / 30, xform 23 / 23.

```c
#include <stdint.h>
/* fire: 4-neighbour average, decay, clamp at 0 */
void fire(uint8_t *dst, const uint8_t *src, int w, int n, uint8_t decay) {
  for (int x = 0; x < n; x++) {
    int s = (src[x-1] + src[x+1] + src[x+w] + src[x+2*w]) >> 2;
    s -= decay; dst[x] = s < 0 ? 0 : s;
  }
}
/* rotozoom: affine walk over a 256x256 texture */
void roto(uint8_t *dst, const uint8_t *tex, uint32_t u, uint32_t v, uint32_t du, uint32_t dv, int n) {
  for (int x = 0; x < n; x++) {
    dst[x] = tex[((v >> 16) & 255) * 256 + ((u >> 16) & 255)];
    u += du; v += dv;
  }
}
/* Q16.16 multiply and one matrix row */
int32_t q16mul(int32_t a, int32_t b) { return (int32_t)(((int64_t)a * b) >> 16); }
int32_t xform(const int32_t *m, int32_t x, int32_t y, int32_t z) {
  return q16mul(m[0],x) + q16mul(m[1],y) + q16mul(m[2],z) + m[3];
}
/* tunnel: a precomputed u16 map into a 64 KB texture */
void tunnel(uint8_t *dst, const uint8_t *tex, const uint16_t *map, uint32_t off, int n) {
  for (int i = 0; i < n; i++) dst[i] = tex[(map[i] + off) & 0xffff];
}
/* plasma: separable, one row table plus a column value */
void plasma(uint8_t *dst, const uint8_t *rowt, uint8_t colv, int n) {
  for (int x = 0; x < n; x++) dst[x] = (uint8_t)(rowt[x] + colv);
}
/* voxel: one column's ray over a 256x256 height map, 1/z from a table */
int voxel(const uint8_t *hm, int32_t px, int32_t py, int32_t dx, int32_t dy, int steps, int32_t camh, const int32_t *invz) {
  int ybot = 200;
  for (int s = 1; s < steps; s++) {
    px += dx; py += dy;
    int h = hm[((py >> 16) & 255) * 256 + ((px >> 16) & 255)];
    int y = 100 + ((int64_t)(camh - h) * invz[s] >> 16);
    if (y < ybot) ybot = y;
  }
  return ybot;
}
```
