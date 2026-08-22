# ZigMachine — Sealed Hardware Spec (Option A: memory-mapped)

Status: **draft / proposal**. Date: 2026-08-22.

Goal: distribute the ZigMachine "fake hardware" as a **compiled, un-editable
binary** with a **memory-mapped ABI**, so coders can write effects and improve
ZigOS, but cannot change the machine's behaviour (the constraints *are* the
console's identity). This is the fantasy-console equivalent of "you get the chips
and the memory map, not the schematics."

---

## 1. Layer model

| Layer | Contents | Distributed as | Editable |
|---|---|---|---|
| **Machine** (sealed) | physical framebuffer + compositing/border/raster/plane pipeline; YM2149 + Paula audio chips | `machine-video.wasm`, `machine-audio.wasm` (binaries) + `hardware.zig` API header | **No** |
| **ZigOS** (open) | `LogicalFB`/palette helpers, `printText`, HBL registration, MOD/YM/sample players | Zig source | Yes |
| **Effects / scenes** (open) | demos, effects | Zig source | Yes |

ZigOS + effects + scenes compile into **`demo.wasm`** (the coder's binary).
`hardware.zig` is the only thing the coder sees of the machine: `extern` decls +
address constants, no implementation.

---

## 2. Module topology

```
 main thread                          audio thread (AudioWorklet)
 ┌───────────────────────────┐        ┌──────────────────────────────┐
 │ host (loader.js)          │        │ host (audio-worklet.js)      │
 │  ├─ machine-video.wasm ◄──┼─shared │  ├─ machine-audio.wasm ◄─────┼─shared
 │  │   (SEALED)             │ memory │  │   (SEALED: Paula + YM)    │ memory
 │  └─ demo.wasm  ───────────┘        │  └─ demo-audio (players) ────┘
 │      (ZigOS + effects)             │      part of demo, ZigOS
 └───────────────────────────┘        └──────────────────────────────┘
```

- **Shared linear memory**: both modules on a thread import the *same*
  `WebAssembly.Memory`, so `demo` writes framebuffers/registers directly (fast,
  no per-pixel calls) and the sealed machine reads them.
- **Code is sealed, memory is not.** WASM protects code, not memory: buggy demo
  code can still scribble machine RAM. That is acceptable — the guarantee is
  "you can't recompile the hardware," not "you can't crash it." True memory
  isolation (separate memories + copy-in/out) is a non-goal for v1.

---

## 3. Video hardware — memory map

Fixed geometry (unchanged from today): physical **400×280 RGBA**, visible
**320×200**, borders 40px each side, **4 planes**, **256-colour** RGBA palette
per plane.

The machine reserves a contiguous **video hardware region** and exposes its base
via `hwVideoBase()` (an exported i32). All offsets below are relative to that base;
ZigOS wraps them so effects use names, not raw addresses.

| Region | Offset | Size | Access | Notes |
|---|---|---|---|---|
| Registers | `REG` = 0x0000 | 256 B | R/W | see §4 |
| Palette ×4 | `PAL` = 0x0100 | 4 × 1024 B | R/W | 256 × RGBA per plane |
| Logical FB ×4 | `LFB` = 0x1100 | 4 × 64000 B | R/W | 320×200, 1 byte palette index/pixel |
| Physical FB | `PFB` | 448000 B | **R only** | machine output; host blits it. Not user-writable. |

`LFB(plane) = base + 0x1100 + plane*64000`, `PAL(plane) = base + 0x0100 + plane*1024`.

> The old "write the border directly for a fullscreen scroller" trick is **not**
> part of the ABI. Overscan is a sanctioned machine feature (§4, `RESOLUTION` +
> border HBL), so users get fullscreen legitimately instead of poking `PFB`.

---

## 4. Video registers (offsets from `REG`)

| Offset | Name | Type | Meaning |
|---|---|---|---|
| 0x00 | `RESOLUTION` | u8 | 0 = planes, 1 = truecolor (border-open state) |
| 0x01 | `NB_PLANES` | u8 (ro) | 4 |
| 0x04 | `BACKGROUND` | u32 | border/background RGBA (settable per-scanline in the border HBL) |
| 0x08 | `PLANE_ENABLE[4]` | u8×4 | 1 = plane composited |
| 0x10 | `GLOBAL_HBL_ID` | u16 | border/background HBL handler id (0 = none) |
| 0x20 | `FB_HBL_ID[4]` | u16×4 | per-plane HBL handler id (0 = none) |
| 0x28 | `FB_HBL_POS[4]` | u16×4 | x position at which the per-plane HBL fires |
| 0x30 | `FRAME` | u32 (ro) | frame counter |

---

## 5. Video entry points

**Exports of `machine-video.wasm`** (called by the host each frame):

```
hwVideoBase() i32                 // base of the video hardware region
hwInit() void                     // reset registers/planes
hwClear() void                    // fill PFB with BACKGROUND, run GLOBAL_HBL per row
hwRender() void                   // composite enabled LFBs -> PFB (border/raster/plane trick)
hwPhysicalPtr() i32               // pointer to PFB for the host to blit
```

Per-frame host loop: `hwClear()` → `demo.frame(dt)` → `hwRender()` → blit `PFB`.

**Imports of `machine-video.wasm`** (provided by the host, routed to `demo`):

```
env.hblDispatch(id: u32, plane: u32, line: u32, x: u32) void
```

The machine calls this during `hwClear`/`hwRender` at each HBL point; `demo`
(ZigOS) switches on `id` to the registered Zig handler. Only integer ids cross
the boundary, so the nice `*const fn` handler API stays inside ZigOS.

---

## 6. Audio hardware

Two chips, register-driven, in `machine-audio.wasm` (own shared memory on the
audio thread). Output: stereo f32.

**Paula — 4 sample channels.** Per channel `ch` (registers block per channel):

| Field | Type | Meaning |
|---|---|---|
| `DATA` | u32 | offset in audio RAM of 8-bit signed PCM |
| `LENGTH` | u32 | bytes |
| `LOOP_START` / `LOOP_LEN` | u32 | loop region (LOOP_LEN 0 = one-shot) |
| `RATE` | f32 | playback samples/sec |
| `VOLUME` | u8 | 0..64 |
| `PAN` | i8 | -64..+64 |
| `TRIGGER` | u8 | write 1 to (re)start from DATA |

**YM2149** — 14 registers `YM_R0..YM_R13` (u8), written like the real PSG
(tone/noise/mixer/volume/envelope). Writing `YM_R13` retriggers the envelope
(0xFF = no change), matching real hardware.

**Sample/song RAM**: a region the host copies MOD/YM/sample bytes into; players
reference offsets within it.

**Exports**: `audioBase()`, `audioInit()`, `audioRenderStereo(frames)`,
`audioLeftPtr()`, `audioRightPtr()`, `audioSongPtr()`, `audioSongCap()`.

**Player timing**: players are ZigOS (open) and must run on the audio thread for
sample accuracy. The worklet hosts both modules; per sub-block it calls
`demoAudio.tick()` (user: writes chip registers) then
`machineAudio.renderStereo(block)` (sealed: chips → samples), exactly mirroring
the video `frame → render` split.

---

## 7. The published API header — `hardware.zig`

The only machine artefact coders import. All bodies are `extern` (implemented in
the sealed binary); constants document the memory map.

```zig
// hardware.zig  (shipped with machine-*.wasm; no implementation source)
pub const PHYSICAL_WIDTH = 400;
pub const PHYSICAL_HEIGHT = 280;
pub const WIDTH = 320;
pub const HEIGHT = 200;
pub const NB_PLANES = 4;

pub extern fn hwVideoBase() i32;
pub extern fn hwPhysicalPtr() i32;
pub extern fn hwInit() void;
pub extern fn hwClear() void;
pub extern fn hwRender() void;

// audio
pub extern fn audioBase() i32;
pub extern fn audioInit() void;
pub extern fn audioRenderStereo(frames: u32) void;
// ... register offset constants for PAL/LFB/REG and the audio chips ...
```

ZigOS builds `LogicalFB`, palette setters, `printText`, and
`setFrameBufferHBLHandler(*const fn ...)` on top of these — unchanged API for
effects, so existing scenes keep working after the split.

---

## 8. Build & distribution

- **Machine (you)**: build `machine-video.wasm` + `machine-audio.wasm` from the
  sealed source in a private/separate module. Publish the two `.wasm` binaries +
  `hardware.zig` + this spec. Version them (`ZM_HW_VERSION`, exported).
- **Coders**: `zig build` their `demo.wasm` from ZigOS + effects + scenes,
  importing `hardware.zig`; they never have machine source. `loader.js` +
  `audio-worklet.js` instantiate machine + demo with shared memory and wire the
  imports.
- Compatibility contract: the memory map + exports/imports + version are the ABI.
  Additive changes bump minor; layout changes bump major.

---

## 9. Migration from today's code

1. **Split video**: move `renderPhysicalFrameBuffer` (the border/plane/raster
   compositing) + `physical_framebuffer` + `Color` out of `bootloader.zig` /
   `zigos.zig` into a `machine/video.zig` that becomes `machine-video.wasm`.
   Replace the current global with the register/framebuffer memory region.
2. **Split audio**: `audio/engine.zig` (Paula) + `audio/ym.zig` become
   `machine-audio.wasm`; `mod.zig`/`ym_player.zig` stay in ZigOS (demo side).
3. **ZigOS shim**: reimplement `LogicalFB`, palette, `printText`, HBL registration
   over `hardware.zig` (memory-mapped), keeping the effect-facing API identical.
4. **Host**: `loader.js` instantiates two modules with one shared `Memory`; wire
   `env.hblDispatch`. Same for the worklet.
5. **Prove it**: the `music_debug` scene must run unchanged against the sealed
   machine (it already exercises planes, palettes, HBL rasters, overscan, audio).

---

## 10. Open questions / decisions to make

- **Fixed absolute addresses vs discovered base pointers.** True fixed addresses
  (a reserved linker section) give the authentic "poke 0xFF8240" feel; exported
  base pointers are easier in Zig/wasm and equally functional. Recommend base
  pointers for v1, documented layout, revisit fixed addresses later.
- **Overscan API shape.** Expose border-opening purely via `RESOLUTION` + HBL
  (as today), or add explicit `OVERSCAN` registers? Recommend keeping the
  resolution/HBL mechanism, documented, and dropping direct-PFB hacks.
- **Player ABI on the audio thread.** Confirm the two-module worklet host is
  acceptable, or fall back to a main-thread player + command queue.
- **Cheat prevention.** None beyond code-sealing in v1 (memory not protected).

---

## 11. Repository structure (the reorg)

The seal only holds if the machine source lives **apart** from everything a coder
receives. Split the one `src/` tree into independent build targets:

```
zigmachine/
├── machine/                  # SEALED — private (separate repo or git submodule)
│   ├── video.zig             #   framebuffer + compositing/border/raster/plane pipeline
│   ├── audio/paula.zig       #   4 sample channels
│   ├── audio/ym2149.zig      #   PSG
│   ├── machine_video.zig     #   wasm entry: exports hw*, owns the video memory map
│   ├── machine_audio.zig     #   wasm entry: exports audio*
│   └── build.zig             #   -> machine-video.wasm, machine-audio.wasm, hardware.zig
│
├── sdk/                      # what a coder receives (generated by the machine build)
│   ├── hardware.zig          #   published API header (extern decls + memory map)
│   ├── machine-video.wasm    #   sealed binary
│   ├── machine-audio.wasm    #   sealed binary
│   └── HARDWARE_SPEC.md
│
├── zigos/                    # OPEN — OS/library layer, built ON TOP of sdk/hardware.zig
│   ├── zigos.zig             #   LogicalFB, palette, printText, HBL registry
│   ├── players/{mod,ym_player,sample}.zig
│   ├── loaders.zig
│   └── math/{zalgebra,mat4,quaternion,generic_vector}.zig
│
├── effects/                  # OPEN — reusable effects (starfield_3d, scrolltext, sprite, ...)
├── scenes/                   # OPEN — demos (music_debug, dbug, ...)
├── assets/                   # fonts, logos, music, screens
│
├── demo/                     # the coder's build
│   ├── demo_main.zig         #   wasm entry (boot/frame), imports sdk/hardware.zig
│   ├── floppy.zig            #   scene selection
│   └── build.zig             #   -> demo.wasm  (zigos + effects + scenes)
│
└── web/                      # host
    ├── index.html, loader.js, audio-worklet.js, css/, overlays/
    └── wasm/                 #   machine-*.wasm + prebuilt demo channels
```

Hard rule: **`demo.zig`/`zigos`/`effects`/`scenes` may only `@import("hardware.zig")`
from `sdk/`, never anything under `machine/`.** A tiny build/CI check can enforce
that (grep for forbidden imports), and coders simply don't get `machine/` at all —
they clone the SDK, not the machine repo.

### Current → new mapping

| Today | Moves to |
|---|---|
| `src/bootloader.zig` (render pipeline) | `machine/video.zig` + `machine/machine_video.zig` |
| `src/bootloader.zig` (boot/frame/input glue) | `demo/demo_main.zig` |
| `src/zigos.zig` `physical_framebuffer`, `Color`, compositing | `machine/video.zig` |
| `src/zigos.zig` `LogicalFB`, palette, `printText`, HBL API | `zigos/zigos.zig` (over `hardware.zig`) |
| `src/audio/engine.zig` (Paula) | `machine/audio/paula.zig` |
| `src/audio/ym.zig` | `machine/audio/ym2149.zig` |
| `src/audio_main.zig` (chip surface) | `machine/machine_audio.zig` |
| `src/audio/mod.zig`, `ym_player.zig` | `zigos/players/` |
| `src/effects/*`, `src/scenes/*`, `src/floppy.zig` | `effects/`, `scenes/`, `demo/floppy.zig` |
| `src/utils/*` | `zigos/` (loaders, math, debug, JS) |
| `docs/*.js`, `*.html`, `css/`, `overlays/` | `web/` |

### Two builds

- `machine/build.zig` → the sealed binaries + `sdk/hardware.zig` (run by you only).
- `demo/build.zig` → `demo.wasm`, resolving `hardware.zig` from `sdk/` (run by coders).

Distribution to coders = **`sdk/` + `zigos/` + `effects/` + `scenes/` + `demo/` +
`web/`**, minus `machine/`.

