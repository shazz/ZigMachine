# ZigMachine — Sealed Hardware Spec (Option A: memory-mapped)

Status: **IMPLEMENTED & proven in-browser** — video + audio sealed, repo
reorganised into `hw/`/`zigos/`/`apps/`. Date: 2026-08-22. See §12 for the full
built-vs-deferred status. (§1–§11 below are the original proposal; §12 records
what actually shipped and where it refined the proposal.)

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
| BEAM table | `OFF_BEAM_TABLE` = `PFB` + PFB size | 64 × 4 B | R/W | 1.6.0: the current line's colour-0 writes (§4, "BEAM"). Outside the blitter's window. |

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
| 0x64 | `BEAM_COUNT` | u16 | 1.6.0: colour-0 writes queued for the CURRENT line; the machine sets it back to 0 after the line |
| 0x68 | `BEAM_DROPPED` | u32 | 1.6.0: running count of BEAM writes the machine refused; only `hwInit` zeroes it (the program reads and clears it) |
| 0x6C | `RAM_ARENA_TOP` | u32 | 1.7.0: first byte above the cart's RAM arena (`hwRamAlloc`); 0 = empty. Survives `hwInit`; `hwSetCartHigh` empties it |
| 0x70 | `RAM_ALLOC_FAILS` | u32 (ro) | 1.7.0: refused `hwRamAlloc`/`hwRamRelease` calls since the cart was declared |

### BEAM — mid-line colour-0 writes (1.6.0)

A zero-bitplane ST screen has no pixels: every "pixel" is colour 0 (`$FF8240`)
rewritten by cycle-counted `move.w`s while the beam crosses the line, and the
background IS the picture. BEAM gives the machine that register, with the
68000's limits built in.

The **global HBL** for physical line `y` (0..279) fills `OFF_BEAM_TABLE` with
entries `x << 16 | colour` and sets `BEAM_COUNT`. When the handler returns,
`hwClear()` paints the line: it starts in `BACKGROUND`, and from each accepted
entry's `x` on the line is that entry's colour. The last colour **becomes
`BACKGROUND`**, so the next line starts in it, exactly as `$FF8240` keeps its
value. `BEAM_COUNT` is then set to 0: a list is consumed once, and the HBL must
refill it on every line it wants writes on. `BEAM_COUNT = 0` is the pre-1.6.0
fill, byte for byte.

- **x** is in PHYSICAL low-res pixels, 0..399, the left border starting at 0
  (the same coordinate as `PHYSICAL_WIDTH`), drawn doubled on the 800 raster.
- **colour** is an ST/STE colour word as written to `$FF8240`: each nibble is 3
  bits plus the STE LSB in bit 3, and the 4-bit level × 16 gives the gun, so a
  plain ST colour lands on the `nibble × 32` grid (0..224) that ripped ST palettes
  use, and an STE half-step 16 above it. It is converted to the palette's RGBA
  (`a<<24 | b<<16 | g<<8 | r`), which is what `BACKGROUND` then holds.

The limits the machine enforces (low res is one pixel per 8 MHz cycle):

| Rule | Why (68000) |
|---|---|
| `x` snaps DOWN to a multiple of 4 | the CPU reaches the bus in 4-cycle slots |
| an accepted write is ≥ 8 px after the previous accepted one (so `x` strictly increases) | `move.w Dn,(An)` = 8 cycles, the fastest write there is |
| at most 64 writes a line; `x` < 400 | the table's 64 slots; the line's 400 px. At 8 px a write only 50 fit a line, so the pixel limit bites first |

A write that breaks a rule is **dropped** and counted in `BEAM_DROPPED` — never
silently absorbed. `BEAM_COUNT` above 64 counts the writes that had no slot.
ZigOS: `zg.beam.begin()`, `zg.beam.write(x, st)`, `zg.beam.cells(x0, w, colours)`,
`zg.beam.dropped()` / `clearDropped()` (`libs/zig/effects/beam.zig`). End to end:
`apps/beam_check.mjs` (and its `--break` twin, 4 px writes, which must be caught).

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

**RAM arena (1.7.0)** — malloc for a cart, called by the cart itself:

```
hwRamAlloc(bytes: u32, alignment: u32) u32   // zeroed, aligned (power of two, 1..65536); 0 = refused, counted
hwRamMark() u32                              // the arena's top (0 = no declared high-water, no arena)
hwRamRelease(mark: u32) void                 // free back to a mark; a mark outside [high-water, top] is refused, counted
hwRamAllocFailures() u32                     // REG_RAM_ALLOC_FAILS
```

A bump allocator between the cart's declared high-water (`CART_HIGH`) and the
video region. `hwRamFree()` = window top − max(high-water, arena top), and
`hwRamUsed()` includes the arena, so `hwRamBase() + hwRamUsed()` is still the first
byte nobody owns. The host's `hwSetCartHigh` at every cart load empties the arena
and zeroes the counter. Rules: `machine/arena.zig` (native tests in
`machine/arena_test.zig`); the sealed binary: `apps/ram_check.mjs`; guide:
`docs/MEMORY.md`.

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
| `legacy/bootloader.zig` (render pipeline) | `machine/video.zig` + `machine/machine_video.zig` |
| `legacy/bootloader.zig` (boot/frame/input glue) | `demo/demo_main.zig` |
| `zigos/zigos.zig` `physical_framebuffer`, `Color`, compositing | `machine/video.zig` |
| `zigos/zigos.zig` `LogicalFB`, palette, `printText`, HBL API | `zigos/zigos.zig` (over `hardware.zig`) |
| `hw/audio/engine.zig` (Paula) | `machine/audio/paula.zig` |
| `hw/audio/ym.zig` | `machine/audio/ym2149.zig` |
| `legacy/audio_main.zig` (chip surface) | `machine/machine_audio.zig` |
| `zigos/players/mod.zig`, `ym_player.zig` | `zigos/players/` |
| `zigos/effects/*`, `apps/scenes/*`, `apps/floppy.zig` | `effects/`, `scenes/`, `demo/floppy.zig` |
| `zigos/utils/*` | `zigos/` (loaders, math, debug, JS) |
| `docs/*.js`, `*.html`, `css/`, `overlays/` | `web/` |

### Two builds

- `machine/build.zig` → the sealed binaries + `sdk/hardware.zig` (run by you only).
- `demo/build.zig` → `demo.wasm`, resolving `hardware.zig` from `sdk/` (run by coders).

Distribution to coders = **`sdk/` + `zigos/` + `effects/` + `scenes/` + `demo/` +
`web/`**, minus `machine/`.

---

## 12. Implementation status (2026-08-22)

**Both halves of the seal are built and proven in the browser**: `music_debug`
runs **unchanged** against the sealed video+audio machine at ~60fps. MOD, YM and
raw-sample players all render through the sealed chips (register/setter ABI), with
the 4-channel oscilloscope reflecting real chip output. Verified via
`docs/sealed.html`.

### Built

| Piece | File(s) | Notes |
|---|---|---|
| Memory map (the ABI, single source of truth) | `hw/sdk/memmap.zig` | geometry, register/region offsets, `HW_VIDEO_BASE`, version |
| Published API header | `hw/sdk/hardware.zig` | `extern` hw* decls + re-exported constants |
| **Sealed** video hardware | `hw/video.zig`, `hw/machine_video.zig` | render pipeline + border/raster/overscan, ported 1:1 → `machine-video.wasm` |
| ZigOS over the ABI | `zigos/zigos.zig` | LogicalFB/palette/PFB are now **views** into the shared region; **public API unchanged** so scenes/effects compile as-is |
| **Open** demo entry | `apps/demo_main.zig` | `boot/frame/hblDispatch/isPlaneEnabled` + audio-mirror pointers → `demo.wasm` |
| Two-target build | `build.zig` (`zig build -Dwasm`, or `zig build sealed`) | machine + demo share one memory; demo linked at `--global-base=0x100000` |
| Dual-module host | `docs/sealed.html`, `docs/sealed-loader.js` | instantiates both over one `WebAssembly.Memory`; routes `env.hblDispatch` → demo |
| Audio ABI header | `hw/sdk/audio.zig` | `extern` chip ops + song-RAM map + constants |
| **Sealed** audio chips | `hw/machine_audio.zig` (reuses `hw/audio/engine.zig` = Paula, `hw/audio/ym.zig` = YM2149) | → `machine-audio.wasm`; exposes `machinePaula*` / `machineYmWrite` / mix ops |
| **Open** audio players | `zigos/players/mod.zig`, `zigos/players/ym_player.zig`, `apps/demo_audio_main.zig` | MOD/YM/raw rewritten to drive the chips via the ABI → `demo-audio.wasm` |
| Dual-module audio worklet | `docs/audio-worklet-sealed.js` | machine-audio + demo-audio share one memory on the audio thread |

**How the audio seal holds:** the two audio modules share one memory on the
worklet thread; the open players drive the sealed chips through imported
`machinePaula*`/`machineYmWrite`/`machineMix*` ops (mirroring the video
`hblDispatch` inversion), handing PCM by absolute offset into a reserved shared
**song RAM** (`0x200000`, 1 MiB). Chip DSP math (`engine.zig`, `ym.zig`) is reused
verbatim, so the sound is preserved; only the player↔chip coupling changed from
struct-field pokes to ABI calls.

**How the seal actually holds (key decisions taken):**
- **Two wasm modules, one `WebAssembly.Memory`.** The video region is *not*
  linker-allocated by either module; it lives at a fixed reserved address
  (`HW_VIDEO_BASE = 0x200000`) **above** both modules' data+stacks, so they
  never collide. This is the "you get the memory map, not the schematics" feel
  (§10's fixed-address question) *and* base-pointer simplicity (`hwVideoBase()`).
- **HBL dispatch inversion.** The sealed render loop calls the host import
  `env.hblDispatch(id, plane, line, x)`, routed back into `demo.hblDispatch`,
  which switches on the integer id to the registered Zig handler. **Only ints
  cross the boundary** — the nice `*const fn` handler API stays inside ZigOS.
- **`hwRenderPlane(plane)` instead of a no-arg `hwRender()`** (a refinement of
  §5): the front-end composites 4 transparent stacked canvases, so the machine
  renders one plane at a time — this keeps `music_debug` pixel-identical.
- **The overscan PFB poke** (`music_debug` writes `zigos.physical_framebuffer`
  for the border scroller) is kept working as an **out-of-ABI escape hatch**:
  `physical_framebuffer` is a view into the shared PFB. This is exactly what §2
  ("memory is not sealed, only code is") permits, and is why the scene runs
  unchanged. Replacing it with the sanctioned RESOLUTION+HBL overscan is still
  the open item from §3/§10.

### Reorg — DONE

Repo reorganised into root-level folders: **`hw/`** (sealed machine + `hw/sdk/`
headers), **`zigos/`** (open library: `zigos.zig`, `effects/`, `players/`,
`utils/` incl. math), **`apps/`** (scenes + demo entries), **`legacy/`** (retired
monolithic path). Cross-folder deps use Zig **named modules** (`build.zig`):
`apps` → `zigos` / `players` / `audio_hw`; `zigos` → `hardware`. The seal is
enforced structurally — the open modules can only reach the machine through the
`hw/sdk/` headers, never `hw/` source (`demo.wasm` proven to import zero audio
symbols). Only the active scene (`music_debug`) was migrated to `@import("zigos")`;
the other scenes still carry pre-reorg relative imports and need the same one-line
swap when selected. A CI grep-guard forbidding `apps`/`zigos` → `hw/` imports is
still worth adding.

### Deferred (next steps, in priority order)

1. **Rebuild the prebuilt channels** (`docs/wasm/*.wasm`) against the sealed
   loader. Each of the ~22 non-active scenes needs (a) its imports migrated to
   `@import("zigos")` (one-line-per-import, the same swap `music_debug` got) and
   (b) its own `demo.wasm` build. The new `sealed.html` currently runs the single
   compiled-in scene selected in `apps/floppy.zig`. Several scenes had stale
   pre-seal APIs already (`demo`, `demo_test`, `bladerunners_fullscreen`, `tex`).
2. **Migrate the legacy `index.html`** to the sealed modules, then **delete
   `legacy/`** (`bootloader.zig`, `audio_main.zig`, `sound/` — superseded, no
   longer built). Until then its committed `bootloader.wasm`/`audio.wasm` serve it.

### Overscan (Option B) — PROTOTYPED & proven, PFB poke retired

The overscan finding was: the RESOLUTION+HBL trick only re-reads the 320×200 FB
*into* the borders (edge repeat) — it can't place **independent** content there,
so `music_debug`'s fullscreen scroller needed a new machine feature. That feature
is now built (Fable's Option B, the ST(E) shifter idea, in prototype form):

- **`FB_STRIDE[4]`** register (`hw/sdk/memmap.zig`, reset 320). A plane whose
  stride is **400** (`STRIDE_FULLSCREEN`) is backed by a full **400×280** logical
  framebuffer and composited by the machine across the **whole physical frame**,
  borders included, from that real backing store — no PFB poke.
- The LFB slots were enlarged to physical size (112000 B each; still fits 48
  pages). `LogicalFB.setFullscreen()` (open ZigOS) flips a plane to physical
  coordinates; a dedicated `renderPlaneFullscreen` path in `hw/video.zig` draws
  it (the normal border-trick path is untouched).
- `music_debug`'s scroller was migrated onto a fullscreen plane 2 and the
  `zigos.physical_framebuffer` poke **deleted**. Proven in-browser: the scroller
  spills into both borders, identical look, ~60fps.

**Option B is now the full model** (not just the enlarged-slots prototype):
- **VRAM pool** (`OFF_VRAM`, 512 KiB) replaces fixed per-plane LFB slots; ZigOS
  bump-allocates each plane its framebuffer (**pay-per-use**: a normal plane
  costs 64000, a fullscreen plane 112000 — a 4-normal-plane scene now uses 256 KB,
  not 448 KB).
- **`FB_BASE[4]`** register (the ST(E) "screen base"): each plane's framebuffer
  is a byte offset into the region, so a plane can point anywhere in the pool —
  scroll-by-base, double-buffering, plane sharing all fall out. Reset value is the
  legacy contiguous layout (`defaultFbBase`), so a binary that never touches it is
  unchanged.
- **`FB_STRIDE[4]`** (320/400) and **`HSCROLL[4]`** (fine horizontal scroll,
  wraps within the row) complete the shifter model. `music_debug`'s scroller runs
  on it with the `physical_framebuffer` poke deleted; proven in-browser, ~60fps.

Still open (nice-to-have, not blocking): a `free`/compacting allocator (the bump
allocator leaks a plane's normal buffer when it's upgraded to fullscreen — fine
within the 512 KB pool), `VSCROLL`, and applying `HSCROLL` to the normal
(non-fullscreen) render path (today it's wired on the fullscreen path).

### Overscan v2 — borders are EARNED via the resolution-flicker trick (2026-09-07)

The always-open `setFullscreen()`/`setMediumFullscreen()` API was *beeeeh* — overscan on
a real ST is a **timing exploit**, not a capability flag. Replaced by a trick-gated mode:

- New `FB_MODE_OVERSCAN` (4) + `REG_RES_FLICKER` latch (`0x58`) + `OVERSCAN_MAGIC_X`/
  `OVERSCAN_X_TOL` constants in `machine/sdk/memmap.zig`.
- `setOverscanBuffer()` allocates the 400×280 buffer but keeps borders **closed**; a scene
  opens them by calling `flickerBorder()` (flick `RES_MEDIUM`→`RES_PLANES`, bump the latch)
  from its per-plane HBL, at the magic column, on the border's scanline. Causal
  top-to-bottom; **garbage on a mistimed (off-column) flicker**. Machine side:
  `renderPlaneOverscan` in `machine/video.zig`. Full how-to in `docs/HW_API.md`.
- `setFullscreen()`/`setMediumFullscreen()` **deleted**. First proven on
  `apps/zig/scenes/fullscreen.zig` (in-browser, ~60fps). The scenes that called the old
  API (union*, music_debug, medium_overscan) are migrated to the trick;
  `medium_overscan` awaits a `setMediumOverscan()` medium twin (follow-up).

### Done in this pass (was deferred)

- ✅ `text.zig`/`background.zig` `&fb.fb`-as-`*[64000]u8` fixed to the `[*]u8`
  view (sprite.zig already indexed `fb.fb`, no change). These effects are dormant
  (not in the active demo) but now compile against the sealed `LogicalFB`.
- ✅ **Seal guard** `tools/check_seal.sh` — CI check that fails if `apps/` or
  `zigos/` import `hw/` machine source directly (defence-in-depth on top of the
  named-module boundary).

> **Note — sound not hear-verified.** The audio split was verified by scope +
> clean console (MOD/YM/sample all render); the chip DSP is reused verbatim so it
> *should* be identical, but give it a listen to confirm pitch/quality.

### Build & run

```
export PATH="$HOME/.local/zig/0.16.0:$PATH"
zig build -Drelease=true -Dwasm      # -> docs/machine-video.wasm, docs/demo.wasm, docs/audio.wasm
cd docs && python3 -m http.server 3333   # open /sealed.html  (hard-reload after rebuilds)
```

The legacy monolithic path (`index.html` + `loader.js` + the old committed
`bootloader.wasm`) is left untouched for A/B comparison.

