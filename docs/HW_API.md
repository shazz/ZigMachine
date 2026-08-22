# ZigMachine — Hardware API (HW_API)

The **sealed machine** ABI: everything a coder gets of the hardware is the two
`.wasm` binaries plus the header files `sdk/hardware.zig` (video) and
`sdk/audio.zig` (audio). This document is the human-readable form of that ABI.

> **Golden rule:** you cannot recompile the hardware. You get the memory map and
> the entry points, not the schematics. The constraints *are* the console.
> Everything here is stable ABI — additive changes bump minor, layout changes
> bump major. Version is exported as `hwVersion()` / `audioVersion()`
> (`0x0001_0000` = 1.0.0).

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

Colours are RGBA `u32`, little-endian byte order `R,G,B,A` (i.e.
`a<<24 | b<<16 | g<<8 | r`).

---

## 4. Video entry points (exports of `machine-video.wasm`)

```zig
hwVideoBase() i32        // base address of the video hardware region
hwInit() void            // reset the register block
hwClear() void           // fill PFB with BACKGROUND, fire the global HBL per row, FRAME++
hwRenderPlane(plane) void // composite one logical FB -> PFB (border/raster/plane trick)
hwPhysicalPtr() i32      // pointer to the PFB, for the host to blit
hwPlanesNumber() u8      // 4
hwPhysWidth() u32        // 400
hwPhysHeight() u32       // 280
hwVersion() u32          // 0x0001_0000
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
