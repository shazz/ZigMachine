# ZigMachine — Hardware API (HW_API)

The **sealed machine** ABI: everything a coder gets of the hardware is the two
`.wasm` binaries plus the header files `sdk/hardware.zig` (video) and
`sdk/audio.zig` (audio). This document is the human-readable form of that ABI.

> **Golden rule:** you cannot recompile the hardware. You get the memory map and
> the entry points, not the schematics. The constraints *are* the console.
> Everything here is stable ABI — additive changes bump minor, layout changes
> bump major. Version is exported as `hwVersion()` / `audioVersion()`
> (`0x0001_0200` = 1.2.0).

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

**Scroll planes** (`FB_MODE = 2`): back a plane with a bigger-than-screen buffer
(`setScrollPlane(w, h)`); the visible 320×200 window is panned by moving `FB_BASE`
(`setScroll(x, y)` — zero per-pixel cost), and `HSCROLL` is re-read every scanline so a
per-plane HBL handler can bend each line (`setScrollFine` → sine wobble / shear).

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
hwVersion() u32          // 0x0001_0200
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
(`Blitter.fill/clear/line/triangle/triangleEx/bob/setHalftone`).

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
hwRamUsed() u32          // this cart's static data + stack
hwRamFree() u32          // what is left below the video region
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
