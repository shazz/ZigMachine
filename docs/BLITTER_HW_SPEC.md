# ZigMachine — Blitter Hardware Spec

Status: **v1 IMPLEMENTED** (2026-09-05). Original proposal 2026-08-22. Companion
to `HARDWARE_SPEC.md` (the sealed video/audio machine) and `HW_API.md` (the ABI).

> **v1 implemented** — register block in `hw/sdk/memmap.zig` (base `OFF_BLIT`
> `0x80`), sealed engine in `hw/blitter.zig`, `hwBlit()` export, open wrapper
> `zigos/blitter.zig` (`Blitter.fill/clear/line/triangle/bob`), demo scene
> `apps/scenes/blitter_demo.zig` (a rotating filled-vector cube, ~60fps, proven
> in `sealed.html`). Ops live: **FILL** (solid + halftone), **BLIT** (3-source
> minterm + colour-key cookie-cut + DESC), **LINE** (Bresenham + minterm),
> **TRIANGLE** (deterministic odd-even scanline fill), plus `CYCLES` readback and
> `CLIP`. **Deferred to v2:** raw area fill (`CON.IFE`/`EFE`) and the async/DMA
> cycle-budgeted mode (§6). `TRIANGLE` currently uses a self-contained scanline
> rasteriser rather than the LINE-mask + area-fill two-pass of §4.4.
>
> **1.4.0 (2026-09-13): sources may live in cart RAM.** `CON2.SRC_ABS` (§2, §3)
> lets channels A/B read absolute addresses in the cart window, the video region
> or the ROM window, range-checked per blit. Before it, every BASE was an offset
> from `HW_VIDEO_BASE`, so a cart's own assets (which live below it) could only
> be blitted after copying them into VRAM.

Goal: give the sealed machine an oldskool **blitter** — a fixed-function 2D
drawing coprocessor the open ZigOS/effects drive through memory-mapped registers.
It accelerates the primitives cracktros live on: **cookie-cut bob blits**,
**block copy/fill**, **line drawing**, and — the demoscene money shot — **filled
2D vectors** (triangles/polygons) via hardware **area fill**.

Heritage: the **Amiga blitter** (Agnus), not the ST one. The ST BLiTTER was a
decent masked block-mover with a halftone and 16 logic ops; the Amiga blitter is
the one demos were *built on* — three source channels + one destination, **256
logic minterms**, barrel shifters, a **line mode**, and an **area-fill mode** that
made filled-vector glenz objects practical. That is the model here (recast for
this machine's chunky pixels). See "Authenticity" (§8).

---

## 1. What it is (and isn't)

The blitter draws into the **logical framebuffers** — the same chunky 8-bit
palette-index planes the video machine composites (`HW_API.md` §2). So it is a
**chunky 8bpp blitter**: one byte = one pixel = one palette index.

That is the deliberate departure from the Amiga, which is **planar** — its blitter
shovels 1-bit bitplanes, which is *why* it needs barrel shifters (to position a
sprite to an odd pixel inside a 16-bit word) and per-word masks. With a whole byte
per pixel, sub-word alignment vanishes: a "shift" is just a byte X offset, and a
"mask" is a per-pixel **colour key**. Everything else about the Amiga model — the
A/B/C→D channel structure, the 256 minterms, line mode, area fill — carries over
and is what makes this worth building.

It is a **drawing accelerator for the open layer**, sealed so its exact rules
(minterms, fill parity, line tie-breaks, clip) are fixed hardware demos rely on
bit-for-bit. Effects call it during `frame()`; it writes the LFBs; the video
machine composites LFBs → physical framebuffer as usual.

```
demo.frame(dt):  set blitter registers  ->  hwBlit()  (sealed: rasterise into an LFB)
                 ... repeat per primitive ...
then, per plane:  hwRenderPlane(i)       (sealed: composite LFB -> PFB)
```

Integration: the blitter lives **inside `machine-video.wasm`** (same thread and
shared memory as the framebuffers it draws into). One new export, `hwBlit()`,
executes the command in the register block. ZigOS drives it; no new host wiring.

---

## 2. Addressing model (forward-compatible with the VRAM video model)

Every channel reads/writes pixels by **base + stride** (Amiga "pointer + modulo"),
matching the shifter video model (`HARDWARE_SPEC.md` §12, Option B):

```
pixel(x, y) address = BASE + y * STRIDE + x        (one byte per pixel)
```

- Today's fixed 320×200 plane: `BASE = LFB(plane)`, `STRIDE = 320`.
- VRAM/stride model: `BASE`/`STRIDE` are whatever the coder allocated (e.g. a
  400-wide fullscreen buffer). No blitter change needed.

Four channels, each with its own `BASE`/`STRIDE` (the Amiga's four DMA channels):
**A**, **B**, **C** (sources) and **D** (destination). Any can point at any plane
or an off-screen scratch buffer, so you can blit plane→plane, cookie-cut a bob
over a background, or accumulate a fill mask off-screen.

**Where BASE points (since 1.4.0).** By default a BASE is an offset in the video
region. With `CON2.SRC_ABS` set, `A_BASE`/`B_BASE` are **absolute** linear
addresses, so a source can be a cart's own RAM: an `@embedFile` sprite sheet, a
scratch buffer, a ROM-window image. The Amiga's blitter could only reach chip
RAM; this one reads anything a program may hold, and the sealed side checks it:
the whole `W×H` source rectangle must lie inside **one** readable window (cart
RAM `[0x100000, 0x300000)`, the video region, ROM RAM `[0x500000, 0x700000)`),
or the BLIT draws nothing. `D_BASE` is always a video-region offset: the blitter
reads where a program may, and writes only video memory.

---

## 3. Register map (blitter register block)

Offsets within a dedicated blitter block in the video hardware region (base fixed
by `hw/sdk/memmap.zig`). Word/long fields little-endian.

| Offset | Name | Type | Meaning |
|---|---|---|---|
| `0x00` | `COMMAND` | u8 | op run on `hwBlit()`: 0 NOP · 1 BLIT · 2 FILL · 3 LINE · 4 TRIANGLE |
| `0x01` | `MINTERM` | u8 | logic function `LF` — the 256-way truth table of A,B,C (see §5) |
| `0x02` | `CON` | u8 | control: bit0 `USEA` bit1 `USEB` bit2 `USEC` (channel enables) · bit3 `KEY_EN` (colour-key cookie-cut) · bit4 `IFE` (inclusive area fill) · bit5 `EFE` (exclusive area fill) · bit6 `DESC` (descending copy) · bit7 `CLIP_EN` |
| `0x03` | `STATUS` | u8 (ro) | bit7 `BUSY` (see §6) |
| `0x04` | `COLOR` | u8 | foreground index (FILL/LINE/TRIANGLE, halftone FG) |
| `0x05` | `BG_COLOR` | u8 | halftone / fill background index |
| `0x06` | `COLOR_KEY` | u8 | index treated as transparent (the chunky "mask", when `KEY_EN`) |
| `0x07` | `CON2` | u8 | control, second byte (1.4.0): bit0 `SRC_ABS` (A/B BASE are absolute addresses, range-checked, see §2) |
| `0x08` | `A_BASE` `A_STRIDE` | u32,u16 | channel A source (mask/data) |
| `0x10` | `B_BASE` `B_STRIDE` | u32,u16 | channel B source (image data) |
| `0x18` | `C_BASE` `C_STRIDE` | u32,u16 | channel C source (background) |
| `0x20` | `D_BASE` `D_STRIDE` | u32,u16 | channel D destination |
| `0x28` | `W` `H` | u16×2 | blit width/height in pixels (BLIT/FILL) — the Amiga `BLTSIZE` |
| `0x2C` | `X0` `Y0` | i16×2 | dst pos (BLIT/FILL) · line start · triangle v0 |
| `0x30` | `X1` `Y1` | i16×2 | line end · triangle v1 |
| `0x34` | `X2` `Y2` | i16×2 | triangle v2 |
| `0x38` | `CLIP_X` `CLIP_Y` | u16×2 | clip rect origin (`CLIP_EN`) |
| `0x3C` | `CLIP_W` `CLIP_H` | u16×2 | clip rect size |
| `0x40` | `HALFTONE[16]` | u16×16 | 16×16 1-bit pattern; bit set → `COLOR`, clear → `BG_COLOR` |
| `0x60` | `CYCLES` | u32 (ro) | estimated cost of the last op (see §6) |

`MINTERM` is the Amiga `BLTCON0` LF byte verbatim; `CON`'s `IFE`/`EFE`/`DESC`
mirror `BLTCON1`'s fill and descend bits. `A/B/C/D_BASE`+`STRIDE` are the Amiga
`BLTxPT` pointers + `BLTxMOD` modulos.

---

## 4. Operations

All ops honour `MINTERM`/channel enables, the clip rect (`CLIP_EN`), and
framebuffer bounds. Coordinates are signed; off-screen geometry is clipped.

### 4.1 `BLIT` — three-source block transfer / cookie-cut bob
Combine enabled sources A,B,C into D over a `W×H` rect, `D = MINTERM(A,B,C)` per
pixel. The canonical **bob** (cookie-cut): A = the sprite's mask, B = the sprite
image, C = the background under it, minterm `0xCA` = `(A & B) | (~A & C)` — "draw
the image where the mask is set, else keep background." The chunky shortcut:
enable only B with `KEY_EN` and the machine skips `B == COLOR_KEY` (a one-channel
cookie-cut, no separate mask plane). `DESC` copies bottom-up/right-left for safe
overlapping moves (smear/feedback trails).

### 4.2 `FILL` — solid / halftone rectangle
Fill the `W×H` rect at `(X0,Y0)` in D with `COLOR`, or — when a `HALFTONE`
pattern is loaded — the 16×16 tile selecting `COLOR`/`BG_COLOR`. Fast clears and
classic dithered/halftone shading. (A degenerate BLIT with only the constant path.)

### 4.3 `LINE` — Bresenham line mode
Draw `(X0,Y0)`→`(X1,Y1)` in `COLOR` (or halftone stipple — the Amiga line
"texture"), combined via `MINTERM` (use `0x3C`/XOR for reversible wireframe and
for laying **fill-mask edges**). Octant Bresenham with a fixed, documented
tie-break so lines are deterministic. This is the Amiga blitter **line mode**.

### 4.4 Area fill + `TRIANGLE` — the filled-vector path
Filled polygons on the Amiga are two blits: **draw the edges** (line mode, XOR,
one boundary pixel per scanline) into a mask, then **area-fill** (`IFE`/`EFE`)
which sweeps each scanline left→right toggling an inside/outside carry at every
boundary pixel and filling the interior. That parity fill — not a scan-converting
rasteriser — is how glenz/vector objects were filled, and it is exact for any
(even concave, self-touching) outline.

This machine exposes both:
- **Raw area fill** via `CON.IFE`/`EFE` on a `BLIT`/`FILL` over a region whose
  boundary you drew with `LINE` — the authentic Amiga two-pass technique.
- **`TRIANGLE`** as a sealed convenience that does exactly that internally
  (rasterise the 3 edges + parity fill, fixed **odd-even** rule), so the common
  case is one call. Convex/concave polygons: the open layer lays edges with
  `LINE` (XOR) then issues one area-fill — hardware fills any outline.

> Keeping tessellation/ordering/backface policy in open ZigOS while the machine
> owns the fill *rule* is the sealed-machine ethos: the hardware guarantees the
> parity fill; the demo decides the mesh.

---

## 5. Minterms (`MINTERM` — the 256 logic functions)

`D = LF(A, B, C)` per pixel: the 8-bit `MINTERM` is the truth table of the three
source bits, applied across all 8 bits of the chunky index. This is the Amiga's
signature — any boolean combination of three sources in one pass. Useful values:

| MINTERM | D = | Use |
|---|---|---|
| `0xF0` | A | copy A |
| `0xCC` | B | copy B (plain image blit) |
| `0xAA` | C | copy C (dest unchanged) |
| `0xCA` | (A & B) \| (~A & C) | **cookie-cut bob** (A=mask, B=image, C=background) |
| `0x6C` | B ^ C | XOR draw (reversible) |
| `0xEA` | (A & B) \| C | additive over background |
| `0x00` / `0xFF` | clear / set | fast constant fills |

A ZigOS enum names the handful demos actually use; the raw byte stays exposed for
the clever ones. (The chunky twist: minterms act per-bit on the palette *index*,
so they're plane-mix/palette-cycle tricks as much as compositing.)

---

## 6. Start, BUSY, and cost

Wasm memory writes don't run code, so ZigOS sets registers then calls the sealed
export:

```zig
hwBlit() void   // execute COMMAND; sets STATUS.BUSY during, clears it after
```

Execution is synchronous (returns when done); `BUSY` is for symmetry with real
hardware and a future async mode. After each op the machine writes `CYCLES` — an
estimated cost (≈ pixels touched + per-line setup, in the spirit of Amiga blitter
timing) so a demo can budget against a raster/VBL the way it would on metal. The
estimate is fixed hardware, so budgets are portable.

> v2: an **async / DMA** mode where `hwBlit()` queues and the machine drains
> against a per-frame cycle budget, exposing real "blitter didn't finish this
> frame" behaviour and CPU/blitter overlap. Out of scope for v1.

---

## 7. ZigOS wrapper (the open side)

`hw/sdk/hardware.zig` gains `hwBlit()` + the register offsets; open ZigOS wraps
them so effects never touch raw registers:

```zig
// zigos/blitter.zig (open) — sketch
pub fn fill(fb: *LogicalFB, x: i16, y: i16, w: u16, h: u16, color: u8) void;
pub fn bob(dst: *LogicalFB, dx: i16, dy: i16, src: *LogicalFB, sx: i16, sy: i16, w: u16, h: u16, key: u8) void;
pub fn line(fb: *LogicalFB, x0: i16, y0: i16, x1: i16, y1: i16, color: u8, mt: Minterm) void;
pub fn triangle(fb: *LogicalFB, v0: Vec2, v1: Vec2, v2: Vec2, color: u8) void;
pub fn polygon(fb: *LogicalFB, verts: []const Vec2, color: u8) void; // edges + one area-fill
pub fn setHalftone(pattern: [16]u16, fg: u8, bg: u8) void;
```

`dots3d.zig` / `shapes.zig` (the existing filled-vector effects) move onto
`triangle()`/`polygon()`, becoming demonstrations of the blitter and getting the
fixed hardware fill for free.

---

## 8. Authenticity — how it maps to the Amiga blitter

| ZigMachine blitter | Amiga blitter |
|---|---|
| `A/B/C/D_BASE` + `STRIDE` | four DMA channels `BLTxPT` + `BLTxMOD` |
| `MINTERM` (256) | `BLTCON0` LF byte — the 256 minterms |
| `CON.IFE`/`EFE` area fill | `BLTCON1` inclusive/exclusive fill — **filled vectors** |
| `LINE` mode | `BLTCON1` LINE bit — Bresenham line mode |
| `CON.DESC` | `BLTCON1` DESC (descending) for overlapping copies |
| cookie-cut minterm `0xCA` / `KEY_EN` | the classic bob blit (mask/data/bg → dest) |
| `HALFTONE[16]` | — (borrowed from the ST BLiTTER; the Amiga used C/patterns) |
| `CYCLES` readback | blitter timing / `BLTBUSY` budgeting |

**Deliberately dropped** (planar-only machinery): barrel shifters (`ASH`/`BSH`)
and word masks (`BLTAFWM`/`BLTALWM`) — sub-word bitplane alignment, meaningless at
one byte per pixel. Their purpose (odd-pixel masked bob blits) is just an arbitrary
`X` offset + `COLOR_KEY` here.

---

## 9. Open questions / decisions

- **Fixed blitter base inside the video region**, documented in
  `hw/sdk/memmap.zig`, consistent with the video registers.
- **Sync vs. async / DMA overlap.** v1 synchronous + `CYCLES` estimate; the async
  cycle-budgeted mode (real "blitter overran the frame", CPU/blitter parallelism)
  is the strong v2 for demos that want to feel the metal.
- **Area-fill parity vs. a scan-rasteriser for `TRIANGLE`.** Recommend the Amiga
  parity fill (exact for concave/self-touching outlines, authentic) with a fixed
  odd-even rule; document it so shared edges are gap/overlap-free.
- **Sub-pixel vertices.** v1 integer (crisp, cheap); v2 fixed-point vertices if
  glenz objects shimmer, same fill rule.
- **Gouraud / textured triangles.** Out of scope — a later, different machine.
  This blitter is flat-fill + halftone + minterms, true to the era.
- **Depends on nothing.** The base+stride addressing works under both today's
  fixed planes and the VRAM/stride shifter model, so this doesn't block on §12/B.
