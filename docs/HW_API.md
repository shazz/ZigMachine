# ZigMachine — Hardware API (HW_API)

The **sealed machine** ABI: everything a coder gets of the hardware is the two
`.wasm` binaries plus the header files `sdk/hardware.zig` (video) and
`sdk/audio.zig` (audio). This document is the human-readable form of that ABI.

> **Golden rule:** you cannot recompile the hardware. You get the memory map and
> the entry points, not the schematics. The constraints *are* the console.
> Everything here is stable ABI — additive changes bump minor, layout changes
> bump major. Version is exported as `hwVersion()` / `audioVersion()`
> (`0x0001_0B00` = 1.11.0).

The single source of truth for the numbers below is `hw/sdk/memmap.zig` (video)
and `hw/sdk/audio.zig` (audio).

---

## 1. Topology

Two sealed binaries, each sharing ONE `WebAssembly.Memory` with the open coder
module on its thread:

```
 main thread                              audio thread (AudioWorklet)
 machine-video.wasm  ⟷ shared memory ⟷    machine-audio.wasm ⟷ shared memory ⟷
 demo.wasm (ZigOS+scene)                  demo-audio.wasm (ZigOS players)
```

Code is sealed (you can't rebuild the `machine-*.wasm`); memory is **not**
isolated (a buggy demo can scribble hardware RAM — that's accepted). The machine
reaches open code through exactly one callback per side (`hblDispatch`, the audio
chip ops), so no function pointers cross the boundary — only integers/floats.

---

## 2. Video memory map

Fixed geometry: physical **400×280 RGBA**, visible **320×200**, borders 40 px per
side, **4 planes**, 256-colour palette per plane. The machine reserves a
contiguous region at a fixed linear address; `hwVideoBase()` returns it.

| Region | Offset | Size | Access | Notes |
|---|---|---|---|---|
| Registers | `0x0000` | 256 B | R/W | see §3 |
| Palette ×4 | `0x0100` | 4 × 1024 B | R/W | 256 × RGBA `u32` per plane |
| Logical FB ×4 | `0x1100` | 4 × 64000 B | R/W | 320×200, one palette index / pixel |
| Physical FB | `0x3F900` | 448000 B | **R only** | machine output; the host blits it |

`PAL(plane) = base + 0x0100 + plane*1024` · `LFB(plane) = base + 0x1100 + plane*64000`.

The region base is a fixed reserved address (`0x200000`) placed above both
modules' data + stacks, so the two wasm modules never collide in the shared
memory.

---

## 3. Video registers (offsets from the register block)

| Offset | Name | Type | Meaning |
|---|---|---|---|
| `0x00` | `RESOLUTION` | u8 | `0` = planes, `1` = truecolor (border-open state), `2` = medium, **1.17.0** `3` = desk (plane 0 alone at 640x480, see "Desk mode") |
| `0x01` | `NB_PLANES` | u8 (ro) | `4` |
| `0x04` | `BACKGROUND` | u32 | border/background RGBA (settable per scanline in the global HBL) |
| `0x08` | `PLANE_ENABLE[4]` | u8×4 | informational in v1 (the host gates blits via `isPlaneEnabled`) |
| `0x0C` | `TC_FADE[4]` | u8×4 | **1.16.0** plane p's true-colour fade: bits 0..4 coefficient (`0` none … `31` full), bit 5 `1` = toward white, bits 6..7 ignored. Other modes ignore it. See "True-colour fade" |
| `0x10` | `GLOBAL_HBL_ID` | u16 | border/background HBL handler id (`0` = none) |
| `0x14` | `TC_OFS_R[4]` | i8×4 | **1.16.0** plane p's signed red offset, added after the fade (`-128..127`) |
| `0x18` | `TC_OFS_G[4]` | i8×4 | **1.16.0** green offset |
| `0x1C` | `TC_OFS_B[4]` | i8×4 | **1.16.0** blue offset |
| `0x20` | `FB_HBL_ID[4]` | u16×4 | per-plane HBL handler id (`0` = none) |
| `0x28` | `FB_HBL_POS[4]` | u16×4 | x position at which the per-plane HBL fires |
| `0x30` | `FRAME` | u32 (ro) | frame counter (incremented by `hwClear`) |
| `0x34` | `FB_STRIDE[4]` | u16×4 | per-plane row stride in BYTES, = px for the 8-bit modes (320 normal · 400 fullscreen · any SCROLL buffer width; 640 / 800 for a 1.15.0 true-colour plane) |
| `0x3C` | `HSCROLL[4]` | u16×4 | per-plane horizontal offset — **re-read per scanline in SCROLL and (1.10.0) OVERSCAN mode** (line distort): a byte (= pixel) offset added to the line's first byte, no wrap; FULLSCREEN latches it once a frame and wraps within the row |
| `0x44` | `FB_BASE[4]` | u32×4 | per-plane framebuffer screen base (byte offset into the region; the pan point) |
| `0x54` | `FB_MODE[4]` | u8×4 | per-plane render mode: `0` normal · `1` fullscreen (always-open overscan) · `2` scroll · `3` medium · `4` overscan (trick-gated) · **1.15.0** `5` true colour (RGB565, 320×200) · `6` true colour full (RGB565, 400×280, borders open) |
| `0x58` | `RES_FLICKER` | u16 | overscan-trick latch: the SDK bumps it on a `RES_MEDIUM`→`RES_PLANES` flicker so the machine can observe the (untrappable) poke once per scanline |
| `0x5C` | `CART_HIGH` | u32 | the running cart's data+stack high-water, declared by the host at load time (`hwSetCartHigh`). Survives `hwInit`. `0` = undeclared. Backs the RAM instructions in §4c |
| `0x60` | `ROM_HIGH` | u32 | the same for the ROM module's window (`hwSetRomHigh`). `0` = no ROM chip fitted |
| `0x64` | `BEAM_COUNT` | u16 | **1.6.0** colour-0 writes queued for the current line (table at `OFF_BEAM_TABLE`); the machine zeroes it after the line |
| `0x68` | `BEAM_DROPPED` | u32 | **1.6.0** running count of refused BEAM writes; only `hwInit` zeroes it — read and clear it yourself |
| `0x6C` | `RAM_ARENA_TOP` | u32 | **1.7.0** first byte above the cart's RAM arena; `0` = empty. Survives `hwInit`; `hwSetCartHigh` (a new cart) empties it. See §4c |
| `0x70` | `RAM_ALLOC_FAILS` | u32 (ro) | **1.7.0** refused `hwRamAlloc`/`hwRamRelease` calls since this cart was declared |
| `0x74` | `FB_HBL_PURE` | u8 ×4 | **1.8.0** 1 = plane p's HBL handler is pure: it writes only that plane's palette and/or calls `flickerBorder()`, reading tables, what `frame()` wrote and the line. The machine ignores it (its plane-major order is the reference); the board's compositor runs such handlers between other planes' passes of the line and moves each line once. ZigOS sets it in `openBorders`, `copper.install`, `linepal.install` and `setFrameBufferHBLHandlerPure`; `setFrameBufferHBLHandler` clears it (but for the library's flicker handlers). A wrong claim changes the board's picture, which the gate checks (`fpga/tools/video_order_pure.py`) |
| `0x78` | `FB_COPPER` | u16 ×4 | **1.9.0** plane p's copper list at region offset `OFF_VRAM + 16 v` (`0` = none): per-line records the machine applies after the plane's HBL handler and before the line (PAL, PALREF from a VRAM table, REG HSCROLL, FLICK; 1.10.0 LBASE: the line's source address, the STE video counter).  Format and rules: `machine/copper.zig`, `fpga/review/COPPER_LIST.md`. ZigOS's `copper` builds it for you; `fb.copperList(words)` / `zg.vramWords(n)` for a hand-built list |

**BEAM — mid-line colour-0 writes (1.6.0).** For zero-bitplane screens, where the
picture is colour 0 rewritten mid-line. From the **global** HBL for physical line
`y`, queue up to 64 entries `x << 16 | st_colour` at `OFF_BEAM_TABLE` (region
offset `0x1DBD00`, just above the PFB) and set `BEAM_COUNT`. `hwClear()` then
paints the line from `BACKGROUND`, switching colour at each entry's `x`
(PHYSICAL px 0..399, left border included), and leaves the last colour in
`BACKGROUND` for the next line, as `$FF8240` keeps its value. The colour is an
ST/STE word; its 4-bit STE level × 16 becomes each RGBA gun (`$777` → 224).
The machine enforces the 68000: `x` snaps down to 4, accepted writes are ≥ 8 px
apart and increasing, 64 a line at most, `x` < 400; anything else is **dropped
and counted** in `BEAM_DROPPED`. With `BEAM_COUNT = 0` nothing changes. ZigOS:

```zig
fn hbl(_: *zg.ZigOS, line: u16) void {
    zg.beam.begin();
    zg.beam.cells(0, 8, &row_colours[line]); // 50 cells of 8 px across the whole line
}
```

Full rules and rationale: `docs/HARDWARE_SPEC.md` §4 "BEAM".

**Scroll planes** (`FB_MODE = 2`): back a plane with a bigger-than-screen buffer
(`setScrollPlane(w, h)`); the visible 320×200 window is panned by moving `FB_BASE`
(`setScroll(x, y)` — zero per-pixel cost), and `HSCROLL` is re-read every scanline so a
per-plane HBL handler can bend each line (`setScrollFine` → sine wobble / shear).

**Overscan planes can scroll too** (`setOverscanScrollPlane(w, h)`, `FB_MODE = 4`):
`renderPlaneOverscan()` already reads its buffer through `FB_BASE` with `FB_STRIDE` as
the row pitch, so backing an OVERSCAN plane with a bigger-than-window buffer makes the
full 400×280 window pannable by `setScroll(x, y)` — hardware scroll *and* open borders,
with no machine-side change. Keep the pan inside `0..w-400` / `0..h-280`. The borders
are still earned (flicker below). Since 1.10.0 this path re-reads `HSCROLL` every
line as `FB_MODE = 2` does (a byte offset added to the line's first byte, no wrap), so a
handler or the copper list's `REG HSCROLL` fine-scrolls each line. Used by
`apps/zig/scenes/automation442.zig`.

**Line lists** (1.10.0, copper `LBASE`, `fpga/review/COPPER_LINEBASE.md`): a copper record
can set the plane's line source address: from that line on, line r reads
`v + (r - r0) * stride` (+ `HSCROLL`), the STE's video counter `$FF8205/07/09`; every frame
starts again from `FB_BASE`, which LBASE never writes. Any mode, byte-aligned, `v` in VRAM
or the list stops. Distorters, wobbles, flips and line zooms become data.

### True-colour planes — since 1.15.0

`FB_MODE = 5` (`TRUECOLOR`) and `6` (`TRUECOLOR_FULL`): a pixel is a little-endian `u16`
**R5 G6 B5** (`r << 11 | g << 5 | b`) with no palette, the Falcon's hi-colour. The machine
expands it by bit replication (`R8 = r << 3 | r >> 2`, `G8 = g << 2 | g >> 4`, `B8 = b << 3 | b >> 2`:
`0xFFFF` is white, `0x0000` black; Hatari's Videl conversion is the same formula) and writes it
with alpha 255. It is a plane like the others, through the same line loop: planes over and under
it, its own HBL handler, its copper list (LBASE, REG HSCROLL, FLICK; PAL / PALREF write a palette
it never reads), HSCROLL and the board's dirty lines all work.

| Mode | Buffer | Lines | Into the raster | HBL line numbers |
|---|---|---|---|---|
| `5` | 320×200, stride 640 B | 40..239 | doubled, from x 80 | logical 0..199 |
| `6` | 400×280, stride 800 B | 0..279 | doubled, from x 0, borders open (nothing to earn) | physical 0..279 |

- `FB_STRIDE`, `HSCROLL` (re-read every line, after the handler and the record, as in SCROLL
  mode, no wrap) and an LBASE are **byte** offsets. **Bit 0 of a line's address is ignored**: an
  odd `FB_BASE`, LBASE, `HSCROLL` or stride shows the even pixel below (the STE's `$FF820D` has no
  bit 0 either). Line `r` reads `(base + (r - r0) * stride + HSCROLL) & ~1`.
- No colour key: a true-colour plane covers everything under it where it draws. Put an 8-bit plane
  with transparent entries over it for sprites or text.
- ZigOS: `const tc = fb.setTruecolorPlane(.window)` (or `.full`) returns a `zg.tc.Fb`
  (`row`, `put`, `put2` two pixels a 32-bit store, `fill`, `copyRect`); `zg.tc.rgb565(r, g, b)`;
  `zg.truecolorBuffer(.window)` a second buffer and `fb.showTruecolor(next)` to flip to it.
  The u8 drawing methods (`setPixelValue`, `printText`, blits by pixel) do not apply.
- Cost on KESTREL: one plane pass a line, as a normal or overscan plane (the fetch is twice the
  bytes). `apps/zig/scenes/mpp_truecolor.zig` mode 3 is the worked example; the design and its LUT
  bill: `fpga/review/TRUECOLOR_PLANE.md`, `decisions.md` 2026-11-02 "True-colour plane".

### True-colour fade — since 1.16.0

On the Falcon a true-colour fade rewrote every pixel. Here the machine fades the pixel where it
expands it: a brightness fade toward black or white (GBA `BLDY`, SNES `INIDISP`) then a signed
offset per channel (the Saturn's colour offset: tints and flashes). A fade, a flash or a tint is
**one register write** (four bytes per plane: `TC_FADE`, `TC_OFS_R/G/B`), like a palette fade;
the pixels never change. All zero (the reset) is the 1.15.0 picture exactly.

For each 8-bit channel `x` of the expanded pixel (the formula above), with `c` = `TC_FADE & 31`,
`white` = bit 5 and `o` the channel's signed offset, in integers:

```
w   = c + (c >> 4)                       0..15, 17..32: coefficient 31 is weight 32 (full)
m   = 32 - w
y   = (x * m + 16) >> 5                  toward black (rounded half up)
y   = 255 - (((255 - x) * m + 16) >> 5)  toward white (the same rule on the complement)
out = min(255, max(0, y + o))            the offset after the fade, clamped
```

Alpha stays 255. Coefficient 0 is the identity whatever bit 5 says; 31 is full black (or white)
whatever the pixel, before the offset: a flash is `TC_FADE = 31` with an offset, or `0` with a large
offset decaying to 0. The browser machine (`machine/video_tc_fade.zig`) and FRESCO
(`fpga/rtl/video/zm_video_tcfade.v`) compute exactly this; `machine/video_tc_fade_test.zig` checks
every channel value, coefficient and direction against the formula.

- **When it is read**: per line, after the line's HBL handler and copper record, as `HSCROLL`. A
  handler or a copper `REG` can change it line by line (a fade curtain, a per-line tint).
- **Copper**: a `REG` may name this plane's `TC_FADE + p`, `TC_OFS_R + p`, `TC_OFS_G + p` or
  `TC_OFS_B + p` (a byte: the value's low byte, bits 15..8 ignored). Another plane's byte stops the
  list. The register keeps what the record wrote (into the next frame), as for `HSCROLL`.
  `zg.tc.copperReg(reg, v)` builds the word.
- ZigOS: `fb.setTruecolorFade(coef, .black | .white)`, `fb.setTruecolorOffset(r, g, b)`;
  `zg.tc.fadeCtl(coef, dir)` is the register byte. TC TEST's key 8 (`apps/zig/scenes/tc_test/fade.zig`)
  is the worked example: a flash, a fade to black, one to white, four bytes a frame.
- Cost on KESTREL: none per pixel for the CPU; FRESCO's painter takes one more clock a pass.
  The board's dirty-line planner counts a fade change as a change to every line of the plane.

### Desk mode — since 1.17.0

`RESOLUTION = 3` (`RES_DESK`) is a screen mode for GEM and tools (Devpac, a text UI), not for demos:
**plane 0 alone, 640x480 palette indices, shown 1:1** in the middle of the 800x600 output (80-pixel
sides, 60-line bars in `BACKGROUND`'s colour). Nothing is composited.

- Plane 0's bytes start at `FB_BASE[0] & ~7` (the board fetches 8-byte beats), stride 640 (`FB_STRIDE`
  is ignored), 307,200 bytes from the VRAM pool (`DESK_FB_BYTES`). Each byte looks up palette 0;
  alpha is ignored (the picture is opaque).
- Ignored in desk mode: every other plane and `PLANE_ENABLE` above plane 0, `FB_MODE`, `FB_STRIDE`,
  `HSCROLL`, every HBL id (global and per plane), `FB_COPPER`, the BEAM table,
  `RES_FLICKER`, the true-colour registers. `FRAME` still counts (`hwClear` does only that).
- **The bars are `BACKGROUND`** (since 9 Nov 2026, still 1.17.0): its R, G and B, alpha ignored, as
  the border in the plane modes. Like the mode, the colour is the one stored before the VBL and holds
  for the whole next frame, bars above and below alike (a store after the VBL waits a frame). Only a
  store counts: a BEAM line's colour carried into `BACKGROUND` is not seen, and no BEAM runs in desk
  mode anyway. A pixel of the picture the board's fetch missed (an underrun) stays black, never the
  bars' colour. GEM sets white in the desk and puts the old colour back when it leaves; `hwInit` and
  ZigOS's scene reset write black, so the next cart starts black.
- The mode is sampled once a frame, at the VBL: a write mid-frame takes effect from the next frame,
  in both directions. `hwInit` writes `RES_PLANES`, so every boot, chainload and swap leaves it.
- **Ask first:** `hwDeskAvailable()` is 1 where the mode exists (the browser, the native host, a
  board bitstream with it); 0 on an older bitstream, where a desk cart would show garbage.
- **Single buffer, as the ST:** the board's scanout reads plane 0 live while the cart draws, so a
  redraw can show half-done for one frame (the browser shows the plane as `frame()` left it). A cart
  that wants no tearing keeps two buffers and flips `FB_BASE[0]`, which the board takes at the VBL.
  A palette write mid-frame shows from the line being scanned on the board, from the next frame in
  the browser. No hash can see either difference.
- The host shows the picture through `hwRenderDesk(0)` and `hwRenderDesk(1)` (§4): the top and
  bottom 640x240 halves as RGBA in the PFB (a whole 640x480 picture does not fit in it), and paints
  the bars from `hwDeskBars()`. A desk frame's hash (scene_hash, the native host, hp_sim) is `"desk"`,
  then `hwDeskBars()` as 4 bytes little-endian (R, G, B, 255), then the two halves in order.
- **ZigOS:** `zg.lfbs[0].setDeskPlane()` asks `hwDeskAvailable()`, takes 307,200 bytes 64-aligned from
  the VRAM pool (once a scene), clears them, stores all of palette 0 again (the board's mirror
  only sees stores) and sets `RES_DESK`; it errors and changes nothing otherwise (`DeskUnavailable`,
  `VramFull`, `NotPlaneZero`). `leaveDesk()` goes back to a low-res plane on the same buffer.
  Since 1.17.0 the VRAM pool also has a guard: a plane that does not fit traps instead of drawing
  over the PFB. `apps/zig/scenes/desk_test.zig` (cart 126) is the worked example.
- **The blitter knows a destination only by its stride:** it clips a destination narrower than the
  raster (stride < 800) at 200 rows, the plane height, so a FILL (or any op) on the desk's plane
  stops at row 199. Draw below it by pointing `D_BASE` at a lower band (each 200-row band one op,
  clipped to the buffer's 480 rows yourself: the last band would run to row 599); ZigGEM does that
  in `rom/gem/gui/bandfill.zig`. The CPU (`setPixelValue`, text) reaches all 480 rows.
- **The pointer** in the desk is the desk's own: `demo.pointer(x, y, ...)` gets 0..639 x 0..479
  (the page maps its canvas there; on the board glass follows the firmware's VMODE word, FPGA_GLASS
  "The mouse"). ZigGEM's desk mode (Options > Set Preferences > Desk, DESKTOP.INF `#E 02`) is the
  reference program: `docs/GEM_DESK_MODE.md` §8.
- The design, the RTL and its LUT bill: `docs/GEM_DESK_MODE.md`, `decisions.md` 2026-11-08 "GEM desk mode".

### Opening the borders (overscan) — the ST timing trick

Overscan is not a flag — you **earn** it, the way real ST demos do, by abusing the
video timing. A plane in **overscan mode** (`setOverscanBuffer()`, `FB_MODE = 4`) holds
a full 400×280 buffer but the machine draws **only the visible 320×200 window** until
you *open* a border with the **resolution-flicker trick**:

- From that plane's **per-plane HBL handler**, call `flickerBorder()` — it flickers the
  resolution register (`RES_MEDIUM` → `RES_PLANES`) and bumps `RES_FLICKER` so the
  sealed machine can see the otherwise-untrappable poke. The handler must be registered
  at the **magic column** `OVERSCAN_MAGIC_X` (= 40; tolerance `OVERSCAN_X_TOL` = 4). The
  machine samples `RES_FLICKER` once per scanline and checks the plane's `FB_HBL_POS`.
- **Which border opens depends on the row you flicker on** (causal, top-to-bottom):
  - flicker in the **top band** (rows 0–39) → top border opens **from that row down**;
  - flicker on a **visible line** (rows 40–239) → **both side borders** open for that
    line (sides must be re-opened every line, as on real hardware);
  - flicker in the **bottom band** (rows 240–279) → bottom border opens from that row down.
- **Miss the magic column** (outside tolerance) and that scanline's border shows
  **garbage** — a mistimed trick, exactly like botching the cycle on a real ST. Not
  flickering at all leaves the border closed (background shows).

To open the whole screen (a static full-overscan picture), register one HBL at
`OVERSCAN_MAGIC_X` that calls `flickerBorder()` on every scanline — top opens at row 0,
both sides every visible line, bottom at row 240. See `apps/zig/scenes/fullscreen.zig`.

> `FB_MODE = 1` (`setFullscreen`, always-open) has been **removed**; overscan is only
> ever the trick-gated mode 4. (The mode-1 render path lingers for legacy back-compat.)

Colours are RGBA `u32`, little-endian byte order `R,G,B,A` (i.e.
`a<<24 | b<<16 | g<<8 | r`).

---

## 4. Video entry points (exports of `machine-video.wasm`)

```zig
hwVideoBase() i32        // base address of the video hardware region
hwInit() void            // reset the register block
hwClear() void           // fill PFB with BACKGROUND, fire the global HBL per row, FRAME++
hwRenderPlane(plane) void // composite one logical FB -> PFB (border/raster/plane trick)
hwBlit() void            // execute the 2D blitter COMMAND (see §4b + BLITTER_HW_SPEC.md)
hwPhysicalPtr() i32      // pointer to the PFB, for the host to blit
hwPlanesNumber() u8      // 4
hwPhysWidth() u32        // 400
hwPhysHeight() u32       // 280
hwVersion() u32          // 0x0001_1200 (1.18.0)
hwDeskActive() u32       // 1.17.0: RESOLUTION is RES_DESK (the host shows the desk picture)
hwRenderDesk(half) void  // 1.17.0: desk rows 240 half .. 240 half + 239 as 640x240 RGBA in the PFB
hwDeskBars() u32         // 1.17.0 (9 Nov): the desk's bars, BACKGROUND as RGBA with alpha 255
hwDeskAvailable() u32    // 1.17.0: 1 where the desk mode exists (see "Desk mode")
hwSetDeskAvailable(v) void // 1.17.0: the board's firmware declares its bitstream's capability
hwAstro(desc, count) u32 // 1.18.0 SPIKE: ASTROLABE, count f64 coprocessor descriptors at desc (docs/ARM_FPU_COPROC.md)
```

**Import it requires** (provided by the host, routed to the open demo module):

```zig
env.hblDispatch(id: u32, plane: u32, line: u32, x: u32) void
```

The machine calls this whenever the render pipeline reaches an HBL point (a row
whose `GLOBAL_HBL_ID`, or a plane whose `FB_HBL_ID[plane]`, is non-zero and whose
`FB_HBL_POS` is hit). ZigOS switches on `id` to the registered Zig handler.

**Per-frame host loop:**

```
hwClear()  →  demo.frame(dt)  →  for each enabled plane: hwRenderPlane(i); blit PFB → canvas[i]
```

`hwRenderPlane` takes a plane id (a refinement of the spec's no-arg `hwRender`)
because the front-end composites four transparent stacked canvases — one per
plane — so each plane is rendered and blitted individually.

---

## 4b. Blitter (2D coprocessor — exports of `machine-video.wasm`)

A fixed-function chunky-8bpp blitter living in the video module. The open layer
sets a register block, then calls `hwBlit()` to execute it (synchronous, v1;
on the board a cart may opt into a lazy wait with `BLIT_ASYNC` at `OFF_BLIT + 0x64`,
see `docs/BLITTER_HW_SPEC.md` §6: the machine itself stays synchronous).
Full model in `docs/BLITTER_HW_SPEC.md`; drive it via `zigos/blitter.zig`
(`Blitter.fill/clear/line/triangle/triangleEx/bob/blitCopy/blitImage/setHalftone`).

- **Register block** at region offset `OFF_BLIT` (`0x80`, below the palettes).
  `COMMAND` (`0` NOP `1` BLIT `2` FILL `3` LINE `4` TRIANGLE `5` QUEUE `6` AFFINE `7` MAP), `MINTERM` (256-way
  A/B/C truth table), `CON` (channel enables · `KEY_EN` cookie-cut · `DESC` ·
  `CLIP_EN`), `COLOR`/`BG_COLOR`/`COLOR_KEY`, four `BASE`+`STRIDE` channels
  (A,B,C sources, D dest), `W`/`H`, `X0..Y2`, `CLIP_*`, a 16×16 `HALFTONE`
  pattern, and `CYCLES` (ro cost estimate). See `hw/sdk/memmap.zig` for offsets.
- **Ops (v1):** FILL (solid or halftone-dithered), BLIT (3-source minterm +
  colour-key cookie-cut + descending copy), LINE (Bresenham combined via
  minterm), TRIANGLE (deterministic odd-even scanline fill, combined via minterm
  so `MT_B` = flat and `MT_OR_BC` = additive **glenz-vector** transparency).
- **Sources in cart RAM — since 1.4.0.** `CON2` (`OFF_BLIT + 0x07`) bit0
  `SRC_ABS` makes `A_BASE`/`B_BASE` absolute linear addresses, so a BLIT can read
  a cart's own `@embedFile` assets and scratch buffers (or the ROM window) with no
  copy into VRAM. The whole `W×H` source rectangle must lie inside ONE readable
  window: cart RAM `[0x100000, 0x400000)`, the video region, or ROM RAM
  `[0x600000, 0x800000)` (the addresses since 1.13.0); otherwise the BLIT draws nothing and `CYCLES` reads 0.
  `D_BASE` stays a video-region offset (the blitter writes only video memory).
  `hwInit()` clears `CON2`, so carts built before 1.4.0 behave exactly as before.
  ZigOS: `Blitter.blitImage(dst, dx, dy, pixels, src_w, sx, sy, w, h, key)`.
- **FILL combines, and a halftone can be declared — since 1.5.0.** `CON2` bit1
  `FILL_MT` makes FILL run its value through `MINTERM` against the destination
  (XOR a pattern in and out again, OR a halftone into what is there); bit2
  `HALFTONE_EN` says the `HALFTONE` pattern is active because the program said
  so, so an ALL-ZERO pattern is density 0 (every pixel `BG_COLOR`) instead of
  "no halftone". Both are opt-in: with the bits clear FILL writes `COLOR`
  straight and the pattern is sniffed, so pre-1.5.0 carts are unchanged.
  ZigOS: `Blitter.fillEx(fb, x, y, w, h, color, .{ .bg = …, .mt = …, .halftone = … })`.
- **QUEUE: many small ops for one `hwBlit()` — since 1.8.0.** `COMMAND` 5 runs a
  list of op descriptors from the QUEUE ring (`OFF_BLIT_QUEUE`, 512 u32 words), word
  `Q_START` (`OFF_BLIT + 0x68`, u16) for `Q_COUNT` words (`+ 0x6A`, u16). A descriptor:
  a header (bits 0..23 the mask of block words that follow, bits 24..31 the op's
  `COMMAND`), then those words, lowest first, into a working copy of the block taken at
  the call; the block is left as it was and `CYCLES` is the sum of the ops' costs.
  Refused (`CYCLES` 0) for an empty list or one past the ring's end. On KESTREL the list
  runs while the cart goes on: a queued op's pixels are only drawn for sure after a
  sync. ZigOS: `zg.blit_queue.Queue` (`fill`, `op`, `set`, `kick`, `flush`). Full rules
  in `docs/BLITTER_HW_SPEC.md` §6. (Built as 1.8.0 on a branch; it reached main with
  CHISEL v2 as 1.11.0.)
- **CHISEL v2 — since 1.11.0** (`docs/BLITTER_HW_SPEC.md` §4.5-4.7, ZigOS
  `zg.chisel_v2`): `COMMAND` 6 **AFFINE** walks `SPAN_COUNT` (`+0x1C`) 24-byte spans
  `(x0, x1, y, 0, u0, v0, du, dv)` at `SPAN_BASE` (`+0x18`, absolute, 4-aligned, in cart
  RAM or the ROM window), each pixel the texel `(u>>16, v>>16)` of the texture at
  `A_BASE`/`A_STRIDE` cut by `U_MASK` (`+0x0E`) / `V_MASK` (`+0x16`) (wrapped, or not
  drawn with `CON2.TEX_CLIP`, bit 6); `COMMAND` 7 **MAP** fills the `W x H` box from a
  u16 `(v<<8|u)` map at `B_BASE`/`B_STRIDE` (absolute, even) plus `U_OFF`/`V_OFF`
  (= `X1`/`Y1`). The texel is B of the minterm, `KEY_EN` skips the key. `CON2` bits 3/4
  `MIRROR_X`/`MIRROR_Y` read a BLIT's sources flipped; bit 5 `COLL_EN` sets `BLIT_COLL`
  (`OFF_BLIT + 0x66`, u8, bit 0, sticky until the program clears it) on any write over a
  non-zero byte; `CON.IFE`/`EFE` (bits 4/5) are the Amiga's area fill on BLIT and FILL,
  per bit, each row's carry from `CON2.FILL_CARRY` (bit 7).
- **Not built:** a cycle-budgeted mode.

```
demo.frame(dt): set blitter regs → hwBlit() (per primitive) → hwRenderPlane(i)
```

---

## 4c. RAM instructions (exports of `machine-video.wasm`) — since 1.2.0

A cart's window is `[0x100000, 0x400000)` — **3 MiB shared** (4 MiB in 1.12.0, 2 MiB `[0x100000, 0x300000)` before) between its own
statics, its stack, and every ROM/library it links (GEM alone takes ~1 MiB). Run
past the top and there is **no trap**: you are writing into the video region, and
the machine dies later, somewhere else. So ask, do not guess:

```zig
hwRamBase() u32          // 0x100000 — first byte of the cart's window
hwRamTop()  u32          // 0x400000 — first byte ABOVE it (= the video region)
hwRamSize() u32          // 0x300000 — the whole window
hwRamUsed() u32          // this cart's static data + stack (+ its RAM arena, 1.7.0)
hwRamFree() u32          // what is left below the video region (above the arena)
```

`hwRamFree()` returns **0** when the host has not declared the cart's high-water
(an older loader). That is deliberately indistinguishable from "full": treat `0`
as *take nothing*, never as *unknown, so assume plenty*.

**How the machine knows.** It owns the memory map but not the cart binary, and
the high-water is baked in by the linker — so the **host** measures it once at
load time (`docs/wasm_hiwater.js`, the same parser `apps/check_fits.mjs` uses)
and declares it:

```js
hwSetCartHigh(high)      // host-only; writes REG_CART_HIGH
```

Language-agnostic: a C or Rust cart imports `hwRamFree` from `env` like any other
entry point. `node apps/ram_check.mjs` tests the instructions against the host
measurement; `node apps/check_fits.mjs <cart.wasm>` reports the same numbers
offline and fails the build if a cart overruns the window.

### The RAM arena — since 1.7.0

malloc for a cart. A module-scope buffer costs its full size in the cart binary
(imported memory is not known to be zero, so the link writes the zeros out) and
in the window before boot; an arena block costs nothing until the cart asks:

```zig
hwRamAlloc(bytes, alignment) u32  // ZEROED block above the high-water; 0 = refused
hwRamMark() u32                   // the arena's top: pass it to hwRamRelease later
hwRamRelease(mark)                // free everything allocated after mark
hwRamAllocFailures() u32          // refusals since this cart was loaded (never silent)
```

- A bump allocator from the cart's high-water (`CART_HIGH`) up to the video region.
  `alignment` is a power of two, 1..65536; `bytes` must be non-zero.
- Refused (returns 0 and bumps `RAM_ALLOC_FAILS`): undeclared high-water, zero
  bytes, a bad alignment, not enough room. `hwRamRelease` of a mark outside
  `[high-water, arena top]` is refused and counted too.
- `hwRamFree()` = `hwRamTop()` − max(high-water, arena top); `hwRamUsed()` counts
  the arena, so `used + free = size` and `hwRamBase() + hwRamUsed()` stays the
  first unowned byte (scenes depack there — memory an allocation later reuses).
- Per cart: `hwSetCartHigh` (every boot, chainload and swap) empties the arena and
  zeroes the counter; `hwInit` leaves both alone.

ZigOS wraps it as `zg.mem` (an `std.mem.Allocator`, `zg.mem.alloc(T, n) ?[]T`,
`mustAlloc`, `mark/release`); C has `apps/c/zigmachine_mem.h`, Rust
`apps/rust/zigmachine_mem.rs`. The whole story: `docs/MEMORY.md`.

### The ROM window — since 1.3.0

The ROM chip gets a **second, separate 2 MiB window ABOVE the video region**, so a
ROM never spends the app's RAM (Phase 2 — `docs/PHASE2_ROM_CHIP.md`):

```zig
hwRomRamBase() u32       // 0x600000 (0x700000 in 1.12.0, 0x500000 before)
hwRomRamTop()  u32       // 0x800000 (0x900000 in 1.12.0, 0x700000 before)
hwRomRamSize() u32       // 0x200000
hwRomRamUsed() u32       // the ROM module's static data + stack
hwRomRamFree() u32       // what is left in ITS window
hwSetRomHigh(high)       // host-only; writes REG_ROM_HIGH
```

No `rom.wasm` is fitted yet, so `hwRomRamFree()` reports **0** — the same answer
as a full window, and for the same reason: *take nothing*.

> **`SHARED_PAGES` went 79 → 112 to cover it, which is a BREAKING change for any
> cart packed before 1.3.0.** A cart declares the imported memory's initial/max,
> so it refuses a memory larger than its max. Everything in `docs/` was rebuilt
> and repacked (`tools/mkdisks.sh`); `node apps/disk_check.mjs` is the check that
> catches a disk left behind.
>
> **1.12.0 raised it again, 112 → 144 (9 MiB)**: the cart window grew to 4 MiB
> `[0x100000, 0x500000)` (the C port of pt2-clone could not load a module in 2 MiB),
> the video region moved to `0x500000` and the ROM window to `[0x700000, 0x900000)`.
>
> **1.13.0 settled on 144 → 128 (8 MiB)**: the cart window is 3 MiB `[0x100000, 0x400000)`,
> the video region is at `0x400000` and the ROM window `[0x600000, 0x800000)`. 8 MiB is all
> the board's CHISEL (23-bit linear addresses) and the seal's linear window reach; 1.12.0's
> 9 MiB never ran on the board.
> Same breaking change, same cure: rebuild every cart (Zig, `apps/c/build.sh`,
> `apps/rust/build.sh`) and repack. Always ask `hwVideoBase()` / `hwRamTop()` /
> `hwRomRamBase()` rather than hard-coding them.

---

## 5. Audio hardware

Two chips in `machine-audio.wasm`, sharing one memory with the open players on
the AudioWorklet thread. Output is stereo `f32` at 44100 Hz.

- **Paula** — 4 sample channels (8-bit signed PCM, Amiga/MOD native), each with
  data pointer/length, loop region, fixed-point step (rate), volume, pan.
- **YM2149** — 3 square-tone channels + noise + 32-step envelope, driven by 14
  registers exactly like the real PSG. Writing register 13 retriggers the
  envelope (`0xFF` = no change).
- **Song RAM** — a reserved shared region (`0x200000`, 1 MiB) the host copies MOD/
  YM/sample bytes into; players and chip reference offsets within it.

### Chip control ABI (exports of `machine-audio.wasm`)

The open players drive the chips only through these:

```zig
machineAudioInit() void
machineClear(n) void                  // zero the stereo bus [0,n)
machineClamp(n) void                  // clamp the stereo bus [0,n) to [-1,1]
machineMixPaula(off, len) void        // mix the 4 sample channels into [off,off+len)
machineRenderYm(off, len) void        // render the PSG into [off,off+len)
machineYmWrite(reg, val) void         // write a YM register (retriggers env on r13)
machinePaulaClearScopes() void
machinePaulaTrigger(ch, data_abs, data_len, loop_start, loop_len, pan) void
machinePaulaSetStep(ch, step) void    // fixed-point (16 frac bits) samples/frame
machinePaulaSetVolume(ch, vol) void   // 0..1
machinePaulaSetPan(ch, pan) void      // -1..+1
machinePaulaSetPos(ch, pos_samples) void
machinePaulaSetActive(ch, on) void
```

`data_abs` is an absolute linear-memory address inside song RAM (use
`sdk/audio.songAddr(offset)`).

**The SID engine** (7 Nov 2026) is not a chip register surface but a renderer the .sid player calls:
cRSID (Hermit, `libs/c/crsid`), a C64's 6502 + SID, light engine, PSID only. On the page it is in
`machine-audio.wasm`; on the board BARD answers the same two imports with the same C, natively
(`fpga/host/audio_sid.c`), and `apps/sid_check.mjs` holds the two to the same samples.

```zig
machineSidLoad(file_abs, len, subtune) u32  // 0 ok, 1 not a .sid, 2 RSID (not supported), 3 a bad length
machineSidRender(dst_abs, n) void           // the next n s16 mono samples at 22050 Hz into dst_abs
machineSidRaw(model) u32                    // raw SID: a C64 with no tune (6581 / 8580, PAL); 0 ok
machineSidWrite(reg, value) void            // one SID register, $D400 + reg (0..0x18), from the next sample
```

Raw SID is a load like any other: a static 2-byte PSID whose init and play are an RTS, so the engine is set up
exactly as for a tune; a write is the 6502's store into cRSID's I/O page. The BARD queue's SID live player uses it.

### The BARD queue (system table 1.12)

One `env` import, the host's: `u32 hostBardAttach(u32 block, u32 lead)` (0 closes; answers 0 where no queue
runs). `block` (16-aligned, in the cart's memory) is `libs/zig/bard.zig`'s: 16 header words (magic `ZMBQ`, the two
ring sizes, the lead; head, dropped and the event tail written by the cart; tail, position, anchored, the event
head and the events lost written by the host), then the commands `{t, addr, value, seq}` and the events
`{t, kind, arg, seq}`, 16 bytes each, `seq` the entry's index. No call after the attach: after each cart frame the
host takes the whole commands (`seq` matches) and writes back. `addr` 0xD400..0xD418 is a SID write, 1 a SID
reset (value = model), 2 a mark (an event back at `t`). On the board BARD reads the ring in DDR: ZIGGY puts the
head in C2S word 5, BARD answers in S2C words 23-31 (`fpga/cycles/snd_mailbox.h`, `bardq_s2c.h`).

### Read-back pointers (for the worklet / scope)

```zig
audioLeftPtr() [*]f32 · audioRightPtr() [*]f32 · audioMaxFrames() u32
audioScopePtr(ch) [*]f32 · audioScopeLen() u32     // per-channel oscilloscope capture
audioYmRegsPtr() [*]u8                              // live YM registers (for visualisers)
audioVersion() u32
```

### Per-block flow (driven by the open player's render loop)

```
machineClear(n)  →  [player writes chip regs via the setters above]
                 →  machineMixPaula(off,len) / machineRenderYm(off,len) per sub-block
                 →  machineClamp(n)     →  worklet copies left/right to the output
```

### MP3 streams (system table 1.11, not a HW version)

Three `env` imports (the host's, like `hostAudioFeed`; `docs/ZIGOS_API.md` 8c has the Zig side):

```c
void hostMp3Ctl(u32 op, u32 arg);     // 0 start, 1 stop, 2 pause (arg 1) / resume (0), 3 the input has ended
void hostMp3Feed(u32 ptr, u32 len);   // append len (<= 32 KiB) bytes of the file to the player's 64 KiB ring
u32  hostMp3Status(u32 which);        // 0 the state word, 1 bytes used (total), 2 frames decoded, 3 BARD's load (per mille)
```

The decoder (pvmp3, `libs/c/pvmp3`) runs where the players run (demo-audio.wasm: the AudioWorklet, BARD) and plays
on **the four Paula channels**, a high byte at VOL 256 and a low byte at VOL 2 a side, `128 h + l = x >> 1`: 15 bits,
bit-exact for 44.1 kHz streams, 6 dB under full scale. While it plays, the channels are its own: no cart Paula
and no Paula sound effects. 32 and 48 kHz streams are converted to 44.1 on the sound side (linear). A system
older than 1.11 refuses a cart that imports them; where no player runs (a sim, the plain native host) every status
is 0.

### The four Paula channels lent to a cart — since 1.14.0

A cart may drive the four Paula channels itself, as an Amiga program does (pt2-clone does:
`apps/ports/pt2/kestrel_paula_hw.c`). Four `env` imports (the host's, like `hostAudioFeed`):

```c
u32  hostPaulaClaim(u32 lead);                 // 1: the cart holds the channels; 0: no Paula here (mix yourself)
void hostPaulaUpload(u32 src, u32 off, u32 len); // copy cart bytes [src, src+len) into chip RAM at off
void hostPaulaWrite(u32 entries, u32 n);         // n timed register writes, 16 bytes each (below)
void hostPaulaRelease(void);                     // give them back (the next cart's reset does too)
```

- **The registers are Amiga Paula's**: `$DFF096` DMACON (bits 0-3, bit 15 set/clear) and per voice
  `$DFF0A0 + 16x`: `+0` LCH, `+2` LCL, `+4` LEN (words; 0 = 65,536), `+6` PER (PAL clock 3,546,895 /
  period), `+8` VOL (0..64), plus KESTREL's `+C` PAN (signed -128..128, the machine's pan / 128; default
  the MOD player's ±0.6, LRRL). LC/LEN are double-buffered as on the Amiga: latched at the DMA start and
  again when the live region runs out (`libs/zig/players/paula.zig`, the model the Hippel player's 68000
  drives). A one-shot is "the sample, then its 2-byte loop", as on the Amiga.
- **Chip RAM** is the 1 MiB song RAM: an LC is an offset in it, and the samples get there by
  `hostPaulaUpload` (the browser's audio thread cannot read the cart's memory; on the board the PCM engine
  reads only the players' memory). The claim zeroes it. Copy what a voice is about to play before the write
  that starts it; an upload lands at once, ahead of the timed writes.
- **Each write is timed**: an entry is `{u32 t, u32 addr, u32 value, u32 0}` (little-endian), `t` the cart's
  own sample clock at 44.1 kHz. The audio side plays each write at its sample: the first batch is placed
  `lead` samples ahead (the claim's argument: the latest a batch can arrive, i.e. the cart's longest frame,
  256..16,384), and later batches keep their distance to it. A batch that arrives late, or with a clock that
  jumped, is re-anchored a lead ahead (`audioPaulaResyncs`).
- **One owner.** The claim stops every player, stream and sample; while the cart holds the channels the host
  refuses every song request, `sndhCall`, effect and stream (the browser warns `... refused, the cart holds the
  Paula channels`, the board logs `ZM PAULA ... refused`).
- No read-back (POS) in 1.14.0: a cart that shows scopes keeps its own (pt2's are its replayer's).

---

## 6. What you build against this

Coders receive `sdk/hardware.zig` + `sdk/audio.zig` + the two `.wasm` binaries and
compile their own `demo.wasm` / `demo-audio.wasm` from **ZigOS + effects + scenes
+ players** — see **ZIGOS_API.md** for that open library. The host
(`sealed-loader.js` + `audio-worklet-sealed.js`) instantiates the machine + demo
pair with one shared memory and wires the callback(s).
