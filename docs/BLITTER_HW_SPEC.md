# ZigMachine — Blitter Hardware Spec

Status: **v1 IMPLEMENTED** (2026-09-05). Original proposal 2026-08-22. Companion
to `HARDWARE_SPEC.md` (the sealed video/audio machine) and `HW_API.md` (the ABI).

> **v1 implemented** — register block in `machine/sdk/memmap.zig` (base `OFF_BLIT`
> `0x80`), sealed engine in `machine/blitter.zig`, `hwBlit()` export, open wrapper
> `libs/zig/blitter.zig` (`Blitter.fill/clear/line/triangle/bob`), demo scene
> `apps/zig/scenes/blitter_demo.zig` (a rotating filled-vector cube, ~60fps, proven
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
>
> **1.5.0 (2026-09-20): FILL joins the rest.** `CON2.FILL_MT` makes `FILL`
> combine through `MINTERM` like `BLIT`/`LINE`/`TRIANGLE` (§4.2), so a patterned
> XOR or OR fill is finally possible; `CON2.HALFTONE_EN` says a halftone is
> active because the program says so, not because the machine found a non-zero
> row, so an ALL-ZERO pattern means density 0 (every pixel `BG_COLOR`) instead of
> "no halftone". Both are opt-in: with the bits clear, `FILL` writes the colour
> straight and the pattern is sniffed, exactly as before 1.5.0.

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
| `0x07` | `CON2` | u8 | control, second byte: bit0 `SRC_ABS` (1.4.0 — A/B BASE are absolute addresses, range-checked, see §2) · bit1 `FILL_MT` (1.5.0 — `FILL` combines through `MINTERM`, §4.2) · bit2 `HALFTONE_EN` (1.5.0 — `HALFTONE` is active by declaration, not by sniffing, §4.2) |
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

All ops honour `MINTERM`/channel enables (`FILL` only with `CON2.FILL_MT`, §4.2),
the clip rect (`CLIP_EN`), and framebuffer bounds. Coordinates are signed; off-screen geometry is clipped.

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
pattern is active — the 16×16 tile selecting `COLOR`/`BG_COLOR`. Fast clears and
classic dithered/halftone shading. (A degenerate BLIT with only the constant path.)

Two bits in `CON2` (1.5.0) widen it, both **opt-in** so that a program written
against 1.4.0 renders identically:

- `CON2.FILL_MT` — the filled value is channel **B** and the destination is
  channel **C**, so `D = MINTERM(0, src, D)`: `0xCC` (`MT_B`) is the plain fill,
  `0x66` XORs the pattern in (and out again next frame), `0xEE` ORs a halftone
  into what is already on the plane. With the bit clear `FILL` ignores `MINTERM`
  entirely — it did until 1.5.0, and callers left the register stale.
- `CON2.HALFTONE_EN` — the `HALFTONE` pattern is active because the program said
  so. With the bit clear the machine decides by looking for a non-zero row
  (pre-1.5.0 behaviour), which makes an all-zero pattern mean "no halftone" —
  backwards for a density ramp, where level 0 must paint every pixel `BG_COLOR`.
  The bit applies to `TRIANGLE`'s halftone too. To turn a halftone off, clear the
  pattern.

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

---

## 10. FPGA implementation

Status: **standalone RTL, proven equal to the machine** (2026-10-03). `fpga/rtl/blitter/`,
top `zm_blit`. The oracle is `machine/blitter.zig` itself, run natively and unchanged.
**On the board SoC in simulation since 2026-10-04** (`fpga/soc/zm_blit_soc.py`, HP2
via `zm_blit_hp.py`, the start through an M-only window from the firmware's
`hwBlit`, `fpga/cycles/bblit.c`; z7 build `--blit`): see the ADR of that date in
`decisions.md`.

### 10.1 Blocks

| File | What |
|---|---|
| `zm_blit_regs.v` | the register block of §3, written the way the CPU writes the region (word index, byte enables); `COMMAND` written non-zero starts the op; writes while `BUSY` are dropped; `STATUS` and `CYCLES` are the only reads |
| `zm_blit_chk.v`, `zm_blit_clip.v` | what `execute()` checks before it draws: the clip rectangle, `opBox`, `destInRegion`, `BlitSetup.load` (zero size, the source rectangle in the region or in ONE readable window). A refusal means "draw nothing, `CYCLES` = 0" |
| `zm_blit_fill.v`, `_blit.v`, `_line.v`, `_tri.v` | one sequencer per op: geometry in, pixels out (x, y, B colour, minterm, channel flags). BLIT walks the clipped box ascending or `DESC`; LINE is the Bresenham of the machine with its `e2` tie-break; TRIANGLE is `crossSpan` with a sequential divider (`_div.v`) for the floor division |
| `zm_blit_px.v` | the pixel unit and the **only** owner of the memory ports: reads the channels the minterm depends on (a minterm that ignores A, B or C never reads it, which cannot be seen), computes `D = LF(A,B,C)` per bit, writes one byte; a keyed pixel is not written and not counted |
| `zm_blit_core.v` | decode, the op FSM (`IDLE, CHK, RUN, DRAIN, FIN`), the one destination address generator `dlin + y*stride + x`, the `CYCLES` model |

`CYCLES` is the machine's: pixels written (BLIT, TRIANGLE), every step of the line
including the clipped ones, `W*H` for FILL (clipped pixels count), 0 when refused
or for an unknown command. A `NOP` leaves it alone.

### 10.2 The memory port

A master with **separate read and write ports**, the video RTL's valid/ready style,
sized for an AXI HP master behind it (`soc/zm_hp.py` is that bridge). Addresses are the
machine's linear byte addresses (the video region is `0x300000 + offset`; SRC_ABS
sources are absolute); the SoC adds its DDR base.

| Port | Signals | Contract |
|---|---|---|
| Read | `rd_req_valid/ready/addr`, `rd_rsp_valid/data[31:0]` | one request per byte, taken on `valid && ready`; the aligned word comes back **at least one clock later, in request order**, no back-pressure; the byte lane is `addr[1:0]` |
| Write | `wr_req_valid/ready/addr/data[31:0]/strb[3:0]` | one byte per request (aligned word, data replicated, one strobe); a read issued after a write is taken sees it |
| Settle | `wr_pending` | high until the memory has landed every write taken (an AXI B response); `BUSY` stays up until it falls, so "not busy" means "the pixels are in DDR" |
| CPU | `cpu_we`, `cpu_waddr[4:0]`, `cpu_be`, `cpu_wdata`, `cpu_raddr`, `cpu_rdata`, `busy` | the snoop style of `zm_video_regs`: writes are seen as the CPU's stores leave its store buffer; reads return `STATUS` (word 0, bit 31) and `CYCLES` (word 24) |

v1 is **one byte per access, one pixel at a time**. Where bursts would help: a BLIT
row is `W` consecutive bytes per channel (one 16-beat burst per channel per row, a
byte-lane shifter for the unaligned ends); a FILL row is a burst of writes with
strobes; the read-modify-write ops (`FILL_MT`, LINE, TRIANGLE, `USEC`) want the
destination row prefetched and the next pixel's reads issued before the previous
write retires. None of that changes a register or a result.

### 10.3 Sharing DDR with the video DMA

The video region lives in PS DDR (FPGA_STEPS: video on **HP1**, the cart CPU's RAM
on **HP0**). The blitter is a third master and takes **HP2**, behind a
32-bit-to-64-bit AXI3 bridge like `zm_hp.py`. No fabric arbitration is needed: the
DDR controller arbitrates the four HP ports, and the video DMA, the only real-time
master, gets the higher QoS / priority (the HP FIFOs and `video_hp_cfg` already exist for
that). The blitter's traffic is bursty and a late pixel only lengthens an op; a late
scanline is a visible tear. Ordering:

- CPU stores to the source pixels and to the register block leave the **same store
  buffer in order**, so the `COMMAND` snoop comes after every store before it;
- `BUSY` includes `wr_pending`, so a CPU load, a compositor pass or the next op after
  "not busy" sees every pixel;
- the machine's `hwBlit()` export becomes "write `COMMAND`, spin on `STATUS`": the same
  synchronous contract (§6) with a real `BUSY`.

### 10.4 Cost (Yosys `synth_xilinx`, xc7, before place and route)

`make -C fpga util` (block `zm_blit`): **2,596 LUT (14.8 % of the 7010), 1,340 FF,
0 BRAM, 8 DSP48**. By module: the checks 750 (a third of it the three range
checks), TRIANGLE 570 (the vertex muxes, the swap, the span clip, the divider), LINE
375, BLIT 220, the 256-bit halftone read 140, the clip 110, the register block 135 +
737 FF (the halftone is 256 of them), the pixel unit 120, FILL 105. Possible cuts if the
budget needs them: the halftone in LUTRAM (about -100 LUT, -256 FF), the check's
bounding box accumulated serially (about -100), an incremental edge walk for
TRIANGLE (faster too).

### 10.5 Throughput (CXXRTL, memory that answers at once, 1 clock read latency)

| Op | clocks per `CYCLES` unit |
|---|---|
| FILL solid or halftone, LINE `MT_B` | **1.0** (a write a clock) |
| FILL_MT / LINE / TRIANGLE combining with the destination (`MT_XOR`, `MT_OR`) | **4.0** (read request, answer, decide, write) |
| ... where the minterm cannot change the destination (`MT_OR`/`MT_XOR` of a 0: a halftone's background bit, the glenz's other-object rows) | **1.0**: no read, no write, still counted in `CYCLES` |
| BLIT copy (B only) | **4.0** per pixel (keyed: 4.0 per candidate pixel) |
| BLIT with A, B and C (cookie-cut) | **6.0** |
| TRIANGLE, `MT_B` | **1.5** for a large one; about 9 for a 16-row one (35 clocks of divider per edge per scanline) |

That is 0.25 to 1 pixel per clock before the memory. Behind an HP port a read costs
+24 clocks unloaded (+62 saturated, at 150 MHz: FPGA_STEPS), so the read-bound ops are
about 25 clocks a pixel there (4 Mpx/s at 100 MHz: a 32x32 bob in 0.26 ms, a full
320x200 copy in 16 ms: too slow), and a solid fill stays near 1 clock a pixel. Pipelined
reads (all three requests in flight, the next pixel's behind them) bring the
read-bound ops to about 3 clocks a pixel whatever the latency, and row bursts to
roughly 1 pixel a clock for a copy, 4 to 8 for a fill (a 64-bit beat carries 8
pixels). That is the first thing to do at integration.

### 10.6 Proof

`fpga/tests/test_rtl_blitter.py` (`make -C fpga check`): `tests/blitter_ref` runs
`machine/blitter.zig` natively on the register writes of a script over a 6 MiB
memory image mapped at the machine's own addresses; `tests/tb/blitter_tb.cpp` plays
the same script into the RTL behind ports that answer like a loaded DDR (ready 3
clocks in 4, reads 1 to 4 clocks late, `wr_pending` held 0 to 5 clocks, junk register
writes while `BUSY`). After **every** op the `CYCLES` readback, `STATUS` and a hash of
the whole 6 MiB must be identical. Scripts: a hand-written set of edge cases (zero
size, fully clipped, negative origin, lines along and one pixel off the clip edge,
degenerate triangles, the region and every window boundary at the byte, `DESC` over an
overlap in both directions) and randomised ops over every op, 12 minterm classes,
clip on/off, halftone declared / sniffed / all-zero, `SRC_ABS`, `DESC`, colour key,
stale registers. 23 break tests (`ZM_RTL_BREAK=1`) each break one rule of the RTL
(minterm index, clip off by one, the Bresenham tie-break, the triangle edge rule, the
floor division, `DESC`, the key, the halftone bit order, the region check, a window
top, `SRC_ABS`, register writes while busy, the byte lane, the `CYCLES` model...) and
all are caught.

### 10.7 Limits

`CON.IFE`/`EFE` (area fill) stay reserved, as in the machine. The register block keeps
no read-back but `STATUS` and `CYCLES` (the region memory holds what was written).
TRIANGLE inputs whose `(bx-ax)*(y-ay)` overflows an `i32` are outside what the Zig
machine defines; the RTL does not model that wrap. Register writes while `BUSY` are
dropped (the machine is synchronous, so a program cannot make them).
