# Retro hardware features, mapped to KESTREL (study, 2026-10-31)

Research study for Matt: "check all 80-90s computers and consoles' nice specific hardware features
(hardware sprites, Mode 7, copper list, ...) that existed, and whether some could be simulated using
CHISEL, custom instructions, ...". No RTL or code was changed for it. Hardware facts carry a source tag
`[n]` (list at the end). LUT and cycle numbers for KESTREL come from the repo docs named beside them;
the LUT estimates for features that do not exist yet are **estimates**, labelled as such.

Related work, not repeated here:
- **ZIGGY ISA extensions / custom instructions**: the parallel study on `study/ziggy-isa`
  (`fpga/review/ZIGGY_ISA_EXTENSIONS.md`, in progress, not yet committed when this was written).
  §2(d) below only states what a GTE-shaped op must do, not how ZIGGY decodes it.
- **A Mode-7 / affine CHISEL op**: studied by the same parallel work. §1 lists every retro feature such
  an op would cover, so it has its value case; §2(b) does not redesign it.
- **Extra sound chips**: `docs/FPGA_AUDIO.md` §7 "the sound-chip lab" already lists the cores, licences
  and the test method. §2(e) ranks them; it does not repeat the table.

## 0. What KESTREL already has (the yardstick)

Read from `docs/HARDWARE_SPEC.md`, `docs/HW_API.md`, `machine/sdk/memmap.zig` (HW 1.9.0),
`docs/BLITTER_HW_SPEC.md`, `fpga/review/COPPER_LIST.md`, `docs/FPGA_AUDIO.md`, `docs/FPGA_SOUND_CPU.md`,
`docs/MUSIC.md`.

| Block | What it gives a cart |
|---|---|
| **FRESCO** (video) | 4 chunky 8-bit planes, each with its own 256-entry RGBA palette; alpha 0 is transparent, partial alpha blends; modes normal 320x200, scroll (window into a bigger buffer), medium 640x200, overscan 400x280 (borders opened by the `RES_FLICKER` trick); `FB_BASE` (screen base), `FB_STRIDE` (row modulo), `HSCROLL` (re-read **every line** in scroll mode); per-plane HBL handler at an x position + global HBL; **BEAM**: mid-line colour-0 writes with 68000 timing rules; **copper list** (1.9.0): per-plane, per-line `PAL` / `PALREF` / `REG` (HSCROLL only) / `FLICK`; ZigOS `zg.copper` (4 entries a line) and `zg.linepal` (255 a line) |
| **CHISEL** (blitter) | Amiga model, chunky: A/B/C to D with 256 minterms, colour-key cookie-cut, DESC, clip, `FILL` (solid, 16x16 halftone, minterm), `LINE` (Bresenham + minterm), `TRIANGLE` (odd-even fill), sources in cart RAM (`SRC_ABS`), `CYCLES` readback. Raw area fill `IFE`/`EFE` is reserved (v2). ~800 cycles of fixed cost an op on the board (`docs/PERF_AUDIT.md`) |
| **ZIGGY** (cart CPU) | VexRiscv rv32im at 100 MHz, posted stores (~2.3 cycles); f32 FPU only in an opt-in build (it no longer fits beside everything). Carts are wasm, compiled to rv32 through wasm2c |
| **BARD** (sound CPU) | VexRiscv RV32I + Zmmul (no divider); runs a 68000 (Musashi) for SNDH, a 6502 for SAP, native players for MOD / XM / Beat Dis / Hippel `.hip` with an emulated Paula |
| **CHORUS** (audio) | YM2149 (jt49), 4 Paula-style PCM channels (volume, pan, loop), POKEY (ours), HDMI audio at 44.1 kHz |
| Board budget | Zynq 7010: 17,600 LUT, 80 DSP48, 60 RAMB36. Measured: 14,888 LUT = 84.6 % (board SoC, `fpga/review/PERFORMANCE_REVIEW.md`, 32 DSP); ~89 % (the brief's current figure); 16,563 LUT = 94.1 % for the largest build (FPU + BARD + CHISEL, `fpga/review/SOC_REVIEW.md` F5); the FRESCO decision of 2026-10-24 quotes 94 % with sys WNS +0.04 ns |

Two consequences shape the whole study:

1. **ZIGGY is fast and FRESCO is the bottleneck.** ZIGGY at 100 MHz is roughly 12x an 8 MHz 68000 per
   clock before counting instruction efficiency, and a store costs ~2.3 cycles. Many 1980s "hardware"
   features existed because the CPU could not redraw the screen in time (sprites, character modes,
   hardware scroll). On KESTREL most of them are cheap in software. What costs frames on the board is
   enabled planes (~0.59 Mc each) and handler CPU time (CLAUDE.md "Board speed").
2. **FRESCO stays frame-serial** (decision of 2026-10-24 in `fpga/review/FRESCO_OPTIONS.md`: idea 1,
   composite at scanout, "is not opened"). So everything that a retro machine composed **at scanout**
   (hardware sprites, the Jaguar Object Processor, the Saturn VDP1/VDP2 layers, Neo Geo / PC Engine
   sprite engines, character modes) maps here to **blits into a plane** (ZigOS over CHISEL, or a new
   CHISEL op), or to **per-line register writes** (the copper list). A sprite unit or tile unit inside
   FRESCO is not on the table, and is not costed below.

## 1. Catalogue

Status: **HAVE** = KESTREL does it today (possibly differently); **EMU** = can be done with what exists
(how in the cell); **NEW** = needs new hardware (where in §2).

### 1.1 Display lists, raster effects, beam racing

| Feature | Machine(s) | What it did | KESTREL today |
|---|---|---|---|
| Copper (WAIT / MOVE / SKIP) | Amiga OCS/ECS/AGA [1] | A coprocessor that waits for a beam position and writes any custom-chip register: palettes, bitplane pointers, sprite pointers, mid-line | **HAVE** for palettes (`PAL`, `PALREF`), HSCROLL, overscan flick, once per line (a handler's x is where it fires, not where its writes take effect: a plane line is composited whole; mid-line changes exist only for colour 0, via BEAM). **NEW (c)**: more registers per line (FB_BASE, BACKGROUND, PLANE_ENABLE), §2 item 1 |
| Display list + LMS + DLI | Atari 800 ANTIC [4] | A list of mode lines; each may reload the memory scan address (LMS) and raise a display-list interrupt | Per-line interrupt: **HAVE** (HBL). Per-line mode: **EMU** (a plane per mode). Per-line LMS = per-line `FB_BASE`: **NEW (c)**, item 1 (browser scroll mode can already jump rows through a large HSCROLL, see §2 item 1) |
| HDMA | SNES [2] | DMA channels that write a table of values to PPU registers each scanline (scroll, Mode 7 matrix, colour math, windows) | **HAVE** for palettes / HSCROLL (copper list). Per-line Mode 7 matrix: belongs to the affine op's per-row parameter table, §2(b) |
| Raster interrupt | C64 VIC-II [5], ST (MFP Timer B), NES mappers, GB STAT/LYC [12] | IRQ on a given line, for splits and colour changes | **HAVE**: per-plane and global HBL handlers, at an x position |
| Mid-line colour changes | ST (cycle-counted `move.w`), Amiga copper | Change a colour register while the beam crosses a line | **HAVE** for colour 0 (BEAM, with the 68000's 4-cycle grid and 8-cycle gap). Plane palettes change per line, not mid-line: a list "WAIT x" op would split FRESCO's paint, low value, not recommended |
| Border opening / overscan | ST (sync tricks), C64 (side-border trick) [5] | Timed register flicker makes the shifter keep displaying in the border | **HAVE**: `RES_FLICKER` from an HBL at `OVERSCAN_MAGIC_X`, or the copper `FLICK` |
| Sprite-0 hit | NES PPU [11] | Status flag when sprite 0 overlaps background: used to time a split | **HAVE** in spirit: HBL handlers make the timing explicit |
| Colour cycling | Amiga, ST, PC (DPaint) | Rotate palette entries to animate a static picture | **HAVE**: palette writes (or a `PALREF` table) |

### 1.2 Scrolling, layers, playfields

| Feature | Machine(s) | What it did | KESTREL today |
|---|---|---|---|
| Hardware fine scroll | STE (HSCROLL + LINEWID) [15], Amiga BPLCON1, ANTIC HSCROL/VSCROL [4], VIC-II VSP (DMA-delay horizontal scroll) [5] | Pixel offset + line modulo so the CPU never moves the picture | **HAVE**: `HSCROLL`, `FB_BASE`, `FB_STRIDE`, scroll mode, `setOverscanScrollPlane` |
| Line scroll | Mega Drive [8], Saturn VDP2 [7], PC Engine | A different horizontal scroll per scanline (water, heat haze, road) | **HAVE**: HSCROLL is re-read per line in scroll mode; copper `REG` writes it without a handler |
| Column scroll / offset-per-tile | Mega Drive (16-px columns) [3][8], SNES modes 2/4/6 [2] | A different vertical scroll per column | **EMU**: CHISEL column copies or a tall plane drawn in strips; no use on the shelf yet. Not worth RTL |
| Vertical per-line scroll, line repeat | Amiga (modulo / BPLxPT per line), VIC-II FLD [5] | Repeat or skip source lines: stretch, reflections, bounce | **NEW (c)** (per-line FB_BASE), item 1; today **EMU** via a handler on browser only (see item 1) |
| Multiple playfields, dual playfield | Amiga (2 x 3 planes), SNES (up to 4 BG), Mega Drive (A, B, window), VDP2 (NBG0-3 + RBG0/1) [7] | Independent layers with their own scroll and priority | **HAVE**: 4 planes, own palette, scroll, base each |
| Per-line / per-tile priority | Amiga BPLCON2, GTIA PRIOR, Mega Drive tile priority bit, SNES | Change which layer is in front, per line or per tile | Fixed plane order. **EMU**: put content on the plane that must be in front; per-tile priority = split the tiles over two planes. A per-line plane-order register is FRESCO work, low value |
| Character / tile modes | Every console, C64, ANTIC, MSX, NES, GB [11][12] | The screen is a map of 8x8 cells: tiny VRAM, cheap scroll | **EMU**: `tilemap.zig` / `tilegrid.zig` draw tiles into a plane (CPU or CHISEL). A hardware tile fetch in FRESCO: not recommended (scanout composition) |
| Window layer / windows | Game Boy window [12], SNES windows (2 per layer + logic) [2], VDP2 W0/W1 + line windows [7] | A HUD layer that does not scroll; per-line clip masks | **HAVE**: a plane is a window layer; CHISEL `CLIP`; per-line masks via copper palette alpha |
| Mosaic | SNES [2], VDP2 | Big-pixel blocky effect | **EMU** in software; vertically by per-line FB_BASE (item 1); horizontally the affine op with a 1/n scale |

### 1.3 Colour tricks

| Feature | Machine(s) | What it did | KESTREL today |
|---|---|---|---|
| HAM6 / HAM8, EHB | Amiga OCS / AGA [1] | Hold-and-modify: each pixel changes one channel of the previous pixel, 4096 (or 262k) colours | **HAVE** the result: 256 colours a plane, 4 planes, 255 new colours a line (`linepal`), per-row palettes (`PALREF`), RGBA entries |
| FLI, interlace colour tricks | C64 [5] | Re-point colour RAM every line for more colours per cell | **HAVE** the result (same as above) |
| Raster bars / gradients | everywhere | One colour register rewritten per line | **HAVE**: `zg.copper`, copper list `PAL` (CLAUDE.md rule: real rasters, full width) |
| Colour math (add/sub/half), translucency | SNES [2], Saturn VDP2, PS1 semi-transparency [9] | Blend two layers per pixel | **HAVE** partly: palette alpha blends a plane over the ones below (alpha blend, not add/sub). CHISEL `MT_OR_BC` for glenz. Additive mode: not recommended |
| Shadow / highlight | Mega Drive [8] | Darken / brighten what is under a sprite | **EMU**: a plane of alpha-black / alpha-white entries |
| True colour | Falcon Videl, Jaguar CRY / RGB16 | 16-bit direct colour | **EMU**: per-row 256-colour palettes (the mpp_truecolor carts) |

### 1.4 Sprites

| Feature | Machine(s) | What it did | KESTREL today |
|---|---|---|---|
| Hardware sprites | C64 8 [5], Amiga 8, NES 64 (8/line) [11], GB 40 (10/line) [12], SMS 64 (8/line), MD 80 (20/line in H40) [16], PCE 64 (16/line) [14], SNES 128 (32/line) [2] | Small images composed at scanout over the background, no redraw cost | **EMU**: CHISEL keyed blits into a plane (`sprite.zig`, `bobs.zig`, `blit_chisel.zig`), erased by dirty rectangle. No scanout sprites (FRESCO is frame-serial). A unified ZigOS sprite engine is §2 item 2 |
| Sprite multiplexing | C64 (raster IRQ re-uses the 8 sprites lower down) [5], Amiga (copper re-points sprite DMA) | More sprites than the hardware has, by reusing them per band | Not needed: blit sprites have no count limit, only a cycle cost (~800 cycles an op + pixels). The CHISEL command list (§2 item 5) removes the per-op CPU cost |
| Sprite H/V flip | NES, GB, MD, SNES, PCE | One sheet, four orientations | **EMU** with the CPU today. **NEW (b)** mirror blit (negative source step), item 3 |
| Sprite scaling / shrink | Neo Geo (shrink only, 380 sprites, chained "sticky" sprites) [6], Lynx Suzy (stretch + tilt per line) [10], Saturn VDP1, Jaguar OP scaled bitmaps [13] | Zoom without CPU work | **EMU**: `blit_stretch.zig` (row by row); **NEW (b)**: the affine op (parallel study) |
| Distorted sprites / quads | Saturn VDP1, 3DO cel engine (forward-mapped quads) [17], Lynx tilt | Map a bitmap onto any quadrilateral | **NEW (b)**: the affine op, if it takes per-row parameters (a quad = per-row start + step) |
| Collision registers | C64 sprite-sprite / sprite-bg [5], Amiga CLXDAT, GTIA, Lynx collision buffer [10] | Hardware says which objects touched | **EMU**: boxes in software (what most games did). **NEW (b)**: a CHISEL "keyed pixel landed on non-key" sticky bit, item 3 |
| Packed sprite data | Lynx (RLE literal / packed lines) [10] | Sprites decoded from packed data on the fly | **EMU**: ZX0 / Pack-Ice unpack at load (`libs/zig/depackers`). Not worth RTL |
| Cursor sprite | Archimedes VIDC (one 32-wide, 3 colours) [18] | Mouse pointer over any mode | **HAVE**: a plane |

### 1.5 Blitters and drawing engines

| Feature | Machine(s) | What it did | KESTREL today |
|---|---|---|---|
| Minterm blitter (A, B, C to D) | Amiga [1] | Any boolean of three sources, shifts, masks | **HAVE**: CHISEL `BLIT`, 256 minterms (chunky: no shifter / masks needed) |
| Line mode | Amiga [1], V9938 `LINE` [19] | Hardware Bresenham | **HAVE**: CHISEL `LINE` |
| Area fill (inclusive / exclusive) | Amiga [1] | Fill between edge pixels drawn one per row: any polygon in one pass | **HAVE** for triangles (`TRIANGLE`); raw `IFE`/`EFE` **NEW (b)**, already spec'd as CHISEL v2, item 3 |
| Halftone, skew, smudge | STE BLiTTER | 16x16 pattern, bit shift, HOP / OP | **HAVE**: CHISEL `HALFTONE` (FILL, LINE, TRIANGLE) |
| VDP commands (HMMM, LMMM, LINE, PSET, SRCH) | MSX2 V9938 [19] | Copies with logical ops, lines, pixel set, search a colour along a line | **HAVE** all but SRCH (software) |
| Blitter with Gouraud + Z | Jaguar [13] | Shaded, depth-buffered spans | **EMU**: Gouraud as a palette-index ramp is cheap on ZIGGY. Z-buffer: not recommended (DDR traffic, not the era's look) |
| Textured, shaded triangles | PS1 GPU (CLUT textures, semi-transparency) [9], N64 RDP | 3D rasterisation | **NEW (b)**: textured = the affine op's triangle variant (parallel study); Gouraud index ramp in `TRIANGLE`, §2 item 8 |
| Async blitter, command / object lists | Amiga (blitter + copper run while the CPU works), Jaguar Object Processor list [13], 3DO cel lists [17] | Queue many ops; the CPU goes on | **NEW (b)**: today `hwBlit()` spins on BUSY. CHISEL command list, item 5 |

### 1.6 Maths coprocessors

| Feature | Machine(s) | What it did | KESTREL today |
|---|---|---|---|
| Hardware multiply / divide | SNES ($4202 / $4204), Lynx Suzy (16x16, 32/16, accumulate) [10] | Fast integer maths for a slow CPU | **HAVE**: ZIGGY rv32im |
| GTE (geometry transformation engine) | PS1 [9] | Fixed-point coprocessor (COP2): RTPS / RTPT = rotate by a 3x3 matrix, translate, perspective divide (an approximating "UNR" divide), with saturation flags; lighting and colour ops | **NEW (d)**: today Q16 code on ZIGGY (`zig3d_fixed`, `fixtrig`). Requirements for the parallel ISA study: §2 item 6 |
| Vector unit (SIMD) | N64 RSP (32 x 128-bit regs, 8 x 16-bit lanes) [20], Falcon DSP56001, Jaguar GPU / DSP RISC | Matrix, audio and clipping work in parallel lanes | **NEW (d)**: packed 16-bit ops are a ZIGGY ISA question (parallel study) |
| Matrix engine | 3DO MADAM [17] | Memory-mapped matrix multiply | as GTE |

### 1.7 Sound

| Feature | Machine(s) | What it did | KESTREL today |
|---|---|---|---|
| PSG square + noise + envelope | ST YM2149, MSX AY, SN76489 (SMS / MD) | 3 tone + noise | **HAVE**: YM2149 (jt49); SN76489 is a lab candidate, low value (the YM covers it) |
| DMA sample channels | Amiga Paula (4 ch, 8-bit, per-channel period / volume) [1], STE DMA (2 ch) [15] | Samples without CPU per sample | **HAVE**: 4 Paula-style channels; STE DMA emulated (`ste_dma.zig`) |
| More PCM voices | Archimedes VIDC (8 channels), SNES S-DSP (8 voices), Neo Geo YM2610 ADPCM | 8 voices in hardware | **EMU**: XM mixes up to 12 voices in software onto the 4 channels. **NEW (e)**: 8 channels, item 7 |
| Wavetable channels | PC Engine (6 x 32 x 5-bit), Konami SCC, GB wave channel, Namco WSG | Short looping waveforms rewritten live | **EMU**: a Paula channel looping a 32-byte buffer is exactly that (limited by the 4 channels) |
| SID (3 voices, ring mod, sync, multimode filter) | C64 [21] | Analog-filtered synth voices | **NEW (e)**: chip core in the sound-chip lab; software SID on BARD is marginal (RV32I, no divider, digi SNDHs already at 43-130 % of BARD) |
| FM synthesis | Mega Drive YM2612 (6 ch, 4 op, DAC), OPL2/3, YM2610 | FM voices | **NEW (e)**: jt12 / jtopl in the lab, GPL-3 |
| POKEY | Atari 8-bit | 4 ch, 16-bit linked pairs, high-pass, poly counters | **HAVE**: ours, in CHORUS, plays SAP via the 6502 on BARD |
| BRR + echo / FIR + pitch modulation + ADSR | SNES S-DSP / SPC700 [22] | 8 compressed-sample voices, 8-tap FIR echo with feedback, a voice modulating the next one's pitch | **EMU**: ADSR / pitch mod are player work (XM). Echo: **NEW (e)** a CHORUS echo stage, item 7 |
| A separate sound CPU | SNES SPC700, MD Z80, Falcon DSP, Neo Geo Z80 | Music runs apart from the game | **HAVE**: BARD |
| Tone controls / mixer | STE LMC1992 over Microwire [15] | Bass, treble, volume | Not present; low value |

### 1.8 System

| Feature | Machine(s) | What it did | KESTREL today |
|---|---|---|---|
| General DMA (memory to VRAM, fill) | SNES, Mega Drive VDP DMA fill / copy | Block moves without the CPU | **HAVE**: CHISEL copies and fills, with `SRC_ABS` from cart RAM |
| Bank switching / mappers | NES, GB, MSX, SMS | More ROM than the address space | N/A: carts are wasm with a 2 MB window + disk streaming |
| Light pen / genlock | many | — | N/A |

## 2. Getting the missing ones, ranked

The ranking weighs value for demos and games (what ported screens and ST-style games on the shelf hit)
against LUT and effort. LUT classes: **S** < 300, **M** 300-1,000, **L** 1,000-2,500, **XL** > 2,500
(all estimates unless a doc number is cited). At ~85-94 % LUT, anything M or above must be paired with
a cut. The cuts already identified: the CHISEL sequencer fold (~850 LUT, PERFORMANCE_REVIEW §1.2 C;
SOC_REVIEW F5 says ~500-700 by folding `chk` + `htb` + `tri`), the CHISEL multiplier pruning (~150), the
jt49 filter (~250), interconnect decode (~200). **A new CHISEL op should be built on the folded edge
walker, not as a fifth sequencer**, so the op and the diet land together.

| # | What | Kind | Retro features it covers | Value | Cost | Effort |
|---|---|---|---|---|---|---|
| 1 | Copper `REG` widened to `FB_BASE`, `BACKGROUND` (global list), `PLANE_ENABLE`, maybe `FB_STRIDE` | (c) | ANTIC LMS per line, Amiga BPLxPT / modulo per line, VIC-II FLD, line repeat, vertical stretch and reflections, vertical mosaic, a plane reused at several heights (sprite bands), global rasters without a handler | **high** (and measured: swedish_newyear's 0.46 Mc needs a BACKGROUND list, FRESCO_OPTIONS 3b) | **S** (estimate 100-300 LUT: per-line base into the plane fetch's row address, a BACKGROUND register copy; the list word already reserves room, decision of 2026-10-24) | 1-2 weeks, both machines, HW minor bump |
| 2 | `zg.sprites`: one ZigOS sprite engine | (a) | Hardware sprites of every console: an OAM-like table (x, y, frame, flip, plane), y-sorted, dirty-rectangle erase ("only modify what needs to be modified"), box collision, CHISEL keyed blits from cart RAM | **high** for games (the opencode ports were judged "average / incomplete", memory note of 10-24) | **0 LUT** | 3-5 days; consolidates `sprite.zig`, `bobs.zig`, `blit_chisel.zig` |
| 3 | CHISEL small-ops bundle: mirror (negative A/B x and y step), collision sticky bit (+ first hit x, y), raw `IFE`/`EFE` area fill | (b) | Sprite H/V flip, kaleidoscopes (blitter v2 note), C64 / Amiga / Lynx collision, Amiga filled vectors of any outline in one pass | medium-high | **S** each (estimate: mirror ~50-150, collision ~30-80 + a C read when enabled, IFE/EFE ~150-300); net negative if done with the fold | 1-2 weeks with the fold; `blitter_tb` + `machine/blitter.zig` as oracle |
| 4 | Affine / Mode 7 CHISEL op (the parallel study) | (b) | SNES Mode 7 (+ HDMA matrix per line), VDP2 rotation planes, Neo Geo shrink, Lynx stretch / tilt, Jaguar scaled objects, Saturn VDP1 / 3DO quads, rotozoom, horizontal mosaic, textured triangles | **high** for demos (Matt's "big one", blitter v2 note) | **L** (estimate; the parallel study costs it) | see parallel study. Ask from this catalogue: take **per-row parameters from a table** (start u, v and du, dv per row), so Mode 7 perspective and quads need no CPU per line |
| 5 | CHISEL command list (async) | (b) | Amiga blitter / CPU overlap, Jaguar OP list, 3DO cel lists | medium-high (sprite-heavy games; `hwBlit()` spins today, ~800 cycles fixed an op). Ops still never overlap (DRAIN between them), so the win is CPU overlap, not blitter throughput, unless the list also relaxes DRAIN | **M** (estimate 300-600: a list fetcher on HP2's read port, an FSM that loads the register block from DDR) | 2-3 weeks; ABI: a list pointer + count, `BUSY` until the list drains |
| 6 | GTE-shaped fixed-point ops | (d) | PS1 GTE RTPS / RTPT, 3DO matrix engine, Lynx MAC, N64 RSP lanes | medium-high for 3D demos (no float per frame; polkadots 2 -> 28 fps after fixed point, CLAUDE.md) | parallel study (DSP-bound: 32 of 80 DSP48 used) | parallel study. Requirements below |
| 7 | CHORUS: 8 PCM channels; then an echo stage | (e) | Archimedes 8 channels, S-DSP 8 voices + echo / FIR, XM without software mixing | medium (music) | 8 ch: **M** (estimate: the PCM block is 636 LUT time-muxed on one DSP, PERFORMANCE_REVIEW; 4 more channels add state, not a multiplier). Echo: **M** + a delay buffer (100 ms stereo 16-bit is 17.6 KB = 4 RAMB36 if that much BRAM is free, else in DDR on HP3) | 2-3 weeks each |
| 8 | Gouraud index ramp in `TRIANGLE` | (b) | Jaguar blitter shading, PS1 Gouraud, Falcon / AGA shaded vectors | medium | **M** (estimate 300-600, 1 DSP) | do it in software first: a 2,000-pixel span triangle is ~5 kc of ZIGGY stores |
| 9 | A new sound chip (SID first, then YM2612) | (e) | C64 SID, MD FM | medium (demoscene: SID tunes; the ST already fakes SID voices on the YM) | **L** each (to be measured in the lab; GPL cores make a distributed bitstream a combined work, `FPGA_AUDIO.md` §7) | the lab already planned |
| 10 | Not recommended | — | scanout sprites / tiles in FRESCO (against the frame-serial decision), Z-buffer channel, copper WAIT-x mid-line palettes, per-line plane priority, LMC1992 tone, SRCH | low | M-XL | — |

### Item 1 in detail: the cheapest real gap

What a list `REG` may write is the whole difference between KESTREL's copper and the Amiga's: the Amiga
copper re-points bitplane DMA mid-frame, which is how line repeat, vertical stretch, reflections and
"one sprite reused lower down" were done, and ANTIC does the same with LMS. KESTREL's `FB_BASE` is read
once per frame (`machine/video.zig` `lfb()`; the board latches it at LATCH). Two notes for whoever builds
it:

- In the browser, `renderPlaneScroll` computes the row as `vy * stride + HSCROLL`, and HSCROLL is a u16
  re-read after the line's handler, so a handler that writes `k * stride + x` already jumps to another
  source row (up to 65,535 bytes ahead). Whether the board's plane fetch does the same add, or wraps
  within the row, must be checked before anyone uses it; if they differ it is a scene_hash mismatch
  waiting to happen. A per-line `FB_BASE` makes the intent explicit and signed.
- `BACKGROUND` in a list gives the global raster (the border colour per line) without a global HBL
  handler, which is the remaining 0.46 Mc of swedish_newyear (FRESCO_OPTIONS 3b).

### Item 6: what a GTE-shaped op must do (for the ISA study)

From the PS1 GTE [9]: the common case is RTPS, done for one vertex or three (RTPT): `v' = R * v + T`
with R a 3x3 matrix of signed 1.3.12, v 16-bit, T 32-bit, then `sx = OFX + H * v'x / v'z` (and y) with
a reciprocal from a table plus one Newton step (the "UNR" divide), results saturated with flags. On
ZIGGY that is 9 MUL + 2 reciprocal-multiplies + shifts and clamps a vertex in Q16 today. What matters
for KESTREL:

- **Carts are wasm compiled by wasm2c**, so a custom instruction only reaches a cart through a ROM or
  machine call (`hw*` export) or a wasm2c pattern, not inline asm. A matrix "load once, then transform N
  vertices from a buffer" call amortises that; a per-vertex instruction does not.
- The divide is the expensive part (BARD has no divider; ZIGGY's divide is iterative). A reciprocal
  table + one Newton step, as the GTE does, is a software win before any RTL.
- DSP budget: a 3-lane 16x16 MAC takes 3 DSP48; 48 are free.

## 3. Top 5 to do next

1. **Widen the copper list's `REG` to `FB_BASE` and `BACKGROUND` (then `PLANE_ENABLE`).** (c), S.
   It is the one retro display trick with no equivalent today (Amiga / ANTIC per-line screen pointers:
   line repeat, stretch, reflections, plane reuse), the list format was designed to take it (decision
   2026-10-24), and BACKGROUND removes a measured 0.46 Mc of handler time on swedish_newyear. Check the
   browser / board HSCROLL row-jump question first.
2. **`zg.sprites`, a ZigOS sprite engine over CHISEL.** (a), 0 LUT. Hardware sprites are the feature
   every console had and KESTREL lacks; with frame-serial FRESCO the right answer is a library, not RTL.
   Games on the shelf (bubblebobble, kickoff2, gnomes) each hand-roll sprites today.
3. **CHISEL mirror + collision bit + raw IFE/EFE, landed with the sequencer fold.** (b), S each, net LUT
   negative with the fold. Flip halves sprite sheets (every console had it), collision is the C64 /
   Amiga register games used, IFE/EFE finishes the Amiga blitter that CHISEL is modelled on.
4. **The affine / Mode 7 op (parallel study), with per-row parameter tables.** (b), L, paid by the fold.
   The single op that covers the most catalogue rows: Mode 7 + HDMA perspective, VDP2 rotation, Neo Geo
   and Lynx scaling, Jaguar objects, 3DO / VDP1 quads, rotozoom. Matt named it the big one.
5. **A CHISEL command list (async).** (b), M. The Amiga's blitter / CPU overlap and the Jaguar / 3DO
   object lists in one mechanism; it turns `zg.sprites` from ~800 cycles of CPU spin an op into a list the
   blitter drains while the cart runs its game logic. The blitter's own per-op DRAIN stays, so the
   frame shortens only where the CPU was the critical path. Do it after 2 and 3 show the per-op cost on the
   board.

Next after these: the GTE-shaped calls (item 6, with the ISA study), 8 PCM channels (item 7), and
running the sound-chip lab with SID first (item 9).

## Sources

Fetched or located during this study (2026-10-31):

1. Amiga Hardware Reference Manual (blitter, copper, area fill, line mode), Amiga Developer CD 2.1 HTML:
   https://amigadev.grimore.org/Hardware_Manual_guide/node012c.html ; https://discmaster.textfiles.com/file/18/Amiga%20Developer%20CD%20v2.1.iso/Reference/HTML/Hardware_Manual_guide/node0122.html ;
   tutorial: https://markwrobel.dk/post/amiga-machine-code-letter12-linedraw2
2. SNES Mode 7 and HDMA: https://sneslab.net/wiki/HDMA ; https://sneslab.net/wiki/2105h ; https://snes.nesdev.org/wiki/DMA ; Fullsnes: https://problemkaputt.de/fullsnes.htm
3. (Mega Drive scroll modes) https://rasterscroll.com/mdgraphics/graphical-effects/row-column-scrolling/
4. De Re Atari (ANTIC display lists, DLI, player-missile): https://www.atariarchives.org/dere/chapt05.php ; https://atariarchives.org/dere
5. VIC-II article (C. Bauer): https://cebix.net/VIC-Article.txt
6. Neo Geo sprites, sticky bit, shrinking: https://wiki.neogeodev.org/index.php/Sprites ; https://wiki.neogeodev.org/index.php/Sticky_bit ; https://wiki.neogeodev.org/index.php/Sprite_shrinking
7. Saturn VDP2 User's Manual (rotation, line scroll, windows): https://www.infochunk.com/saturn/segahtml_en/hard/vdp2/index.htm ; https://www.infochunk.com/saturn/segahtml_en/hard/vdp2/hon/p06_20.htm
8. Mega Drive VDP overview: https://rasterscroll.com/mdgraphics/vdp-overview/
9. PS1 GTE: nocash PSX-SPX https://problemkaputt.de/psx-spx.htm (GTE section); GTE.txt https://otakon273.duckdns.org/Consoles/RomHacking.net/rhdn_20240801/documents/[124]gte.txt ; FPGA GTE https://github.com/Laxer3a/PS-GTE ; UNR divide note https://github.com/BluestormDNA/ProjectPSX
10. Lynx (Suzy sprite engine, collision, multiply / divide): https://mail.retroisle.com/atari/lynx/Technical/Programming/lynxmanual.php
11. NES PPU: https://www.nesdev.org/wiki/PPU (standard reference, not fetched this session)
12. Game Boy Pan Docs (OAM 10 per line, STAT / LYC): https://gbdev.io/pandocs/ ; https://github.com/gbdev/pandocs/blob/ae89342abe259502402247e268db2912ab848314/src/OAM.md?plain=1
13. Jaguar Object Processor and blitter: https://www.mulle-kybernetik.com/jagdox/general.html ; https://emulation.fandom.com/wiki/Atari_Jaguar
14. HuC6270 VDC manual (16 sprites a line): https://www.cpcwiki.eu/imgs/0/05/HuC6270_-_CMOS_Video_Display_Controller_Manual.pdf ; https://datacrystal.tcrf.net/wiki/VDC_Reference_Manual
15. STE hardware scroll, DMA sound, LMC1992 / Microwire: https://atarimagazines.com/startv5n4/enhanced.php ; https://alive.atari.org/alive6/ste.php ; https://discmaster.textfiles.com/view/22208/VECTRONIX2.iso/FILES_01/STE_ADRE.LZH/STEPROGR.DOC
16. Mega Drive sprite limits (80, 20 a line in H40): https://segaretro.org/Sega_Mega_Drive/Sprites
17. 3DO cel / spryte engine (patents): https://patents.google.com/patent/US5596693
18. Acorn VIDC datasheet: https://www.chrisacorns.computinghistory.org.uk/docs/Acorn/Misc/Acorn_VIDC_Datasheet.pdf
19. V9938 Technical Data Book: https://vgamuseum.info/images/doc/yamaha/v9938.pdf ; https://ninerpedia.org/wiki/V9938
20. N64 RSP: https://n64brew.dev/wiki/RSP ; https://n64brew.dev/wiki/RCP
21. SID 6581: standard reference (MOS 6581 datasheet), not fetched this session
22. S-DSP (Anomie, jwdonal update): https://otakon273.duckdns.org/Consoles/RomHacking.net/rhdn_20240801/documents/[191]apudsp_jwdonal.txt

KESTREL facts: the repo docs named in §0, read on `origin/main` b4d4f3b2.
