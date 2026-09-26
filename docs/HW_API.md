# ZigMachine — Hardware API (HW_API)

The **sealed machine** ABI: everything a coder gets of the hardware is the two
`.wasm` binaries plus the header files `sdk/hardware.zig` (video) and
`sdk/audio.zig` (audio). This document is the human-readable form of that ABI.

> **Golden rule:** you cannot recompile the hardware. You get the memory map and
> the entry points, not the schematics. The constraints *are* the console.
> Everything here is stable ABI — additive changes bump minor, layout changes
> bump major. Version is exported as `hwVersion()` / `audioVersion()`
> (`0x0001_0700` = 1.7.0).

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
| `0x00` | `RESOLUTION` | u8 | `0` = planes, `1` = truecolor (border-open state) |
| `0x01` | `NB_PLANES` | u8 (ro) | `4` |
| `0x04` | `BACKGROUND` | u32 | border/background RGBA (settable per scanline in the global HBL) |
| `0x08` | `PLANE_ENABLE[4]` | u8×4 | informational in v1 (the host gates blits via `isPlaneEnabled`) |
| `0x10` | `GLOBAL_HBL_ID` | u16 | border/background HBL handler id (`0` = none) |
| `0x20` | `FB_HBL_ID[4]` | u16×4 | per-plane HBL handler id (`0` = none) |
| `0x28` | `FB_HBL_POS[4]` | u16×4 | x position at which the per-plane HBL fires |
| `0x30` | `FRAME` | u32 (ro) | frame counter (incremented by `hwClear`) |
| `0x34` | `FB_STRIDE[4]` | u16×4 | per-plane row stride in px (320 normal · 400 fullscreen · any SCROLL buffer width) |
| `0x3C` | `HSCROLL[4]` | u16×4 | per-plane horizontal offset — **re-read per scanline in SCROLL mode** (line distort) |
| `0x44` | `FB_BASE[4]` | u32×4 | per-plane framebuffer screen base (byte offset into the region; the pan point) |
| `0x54` | `FB_MODE[4]` | u8×4 | per-plane render mode: `0` normal · `1` fullscreen (always-open overscan) · `2` scroll · `3` medium · `4` overscan (trick-gated) |
| `0x58` | `RES_FLICKER` | u16 | overscan-trick latch: the SDK bumps it on a `RES_MEDIUM`→`RES_PLANES` flicker so the machine can observe the (untrappable) poke once per scanline |
| `0x5C` | `CART_HIGH` | u32 | the running cart's data+stack high-water, declared by the host at load time (`hwSetCartHigh`). Survives `hwInit`. `0` = undeclared. Backs the RAM instructions in §4c |
| `0x60` | `ROM_HIGH` | u32 | the same for the ROM module's window (`hwSetRomHigh`). `0` = no ROM chip fitted |
| `0x64` | `BEAM_COUNT` | u16 | **1.6.0** colour-0 writes queued for the current line (table at `OFF_BEAM_TABLE`); the machine zeroes it after the line |
| `0x68` | `BEAM_DROPPED` | u32 | **1.6.0** running count of refused BEAM writes; only `hwInit` zeroes it — read and clear it yourself |
| `0x6C` | `RAM_ARENA_TOP` | u32 | **1.7.0** first byte above the cart's RAM arena; `0` = empty. Survives `hwInit`; `hwSetCartHigh` (a new cart) empties it. See §4c |
| `0x70` | `RAM_ALLOC_FAILS` | u32 (ro) | **1.7.0** refused `hwRamAlloc`/`hwRamRelease` calls since this cart was declared |

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
are still earned (flicker below), and unlike `FB_MODE = 2` this path does **not**
re-read `HSCROLL`, so there is no per-line fine scroll. Used by
`apps/zig/scenes/automation442.zig`.

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
hwVersion() u32          // 0x0001_0700 (1.7.0)
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
sets a register block, then calls `hwBlit()` to execute it (synchronous, v1).
Full model in `docs/BLITTER_HW_SPEC.md`; drive it via `zigos/blitter.zig`
(`Blitter.fill/clear/line/triangle/triangleEx/bob/blitCopy/blitImage/setHalftone`).

- **Register block** at region offset `OFF_BLIT` (`0x80`, below the palettes).
  `COMMAND` (`0` NOP `1` BLIT `2` FILL `3` LINE `4` TRIANGLE), `MINTERM` (256-way
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
  window: cart RAM `[0x100000, 0x300000)`, the video region, or ROM RAM
  `[0x500000, 0x700000)`; otherwise the BLIT draws nothing and `CYCLES` reads 0.
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
- **Deferred (v2):** raw area fill (`CON.IFE`/`EFE`) and an async/DMA
  cycle-budgeted mode.

```
demo.frame(dt): set blitter regs → hwBlit() (per primitive) → hwRenderPlane(i)
```

---

## 4c. RAM instructions (exports of `machine-video.wasm`) — since 1.2.0

A cart's window is `[0x100000, 0x300000)` — **2 MiB shared** between its own
statics, its stack, and every ROM/library it links (GEM alone takes ~1 MiB). Run
past the top and there is **no trap**: you are writing into the video region, and
the machine dies later, somewhere else. So ask, do not guess:

```zig
hwRamBase() u32          // 0x100000 — first byte of the cart's window
hwRamTop()  u32          // 0x300000 — first byte ABOVE it (= the video region)
hwRamSize() u32          // 0x200000 — the whole window
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
hwRomRamBase() u32       // 0x500000
hwRomRamTop()  u32       // 0x700000
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

---

## 6. What you build against this

Coders receive `sdk/hardware.zig` + `sdk/audio.zig` + the two `.wasm` binaries and
compile their own `demo.wasm` / `demo-audio.wasm` from **ZigOS + effects + scenes
+ players** — see **ZIGOS_API.md** for that open library. The host
(`sealed-loader.js` + `audio-worklet-sealed.js`) instantiates the machine + demo
pair with one shared memory and wires the callback(s).
