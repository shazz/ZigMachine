# ZigMachine — Project Review & Pointers

> Orientation map for picking this project back up. Written 2026-08-22 after a
> cold read of the tree. ZigMachine is a fantasy console written in Zig,
> compiled to `wasm32-freestanding-musl`, rendered to `<canvas>` in the browser.
> Live: https://shazz.github.io/ZigMachine/

## TL;DR — where you stopped

You stopped mid-way through **audio support**, which had left **the build broken**.
There were *three* half-finished audio approaches that don't agree with each other,
plus a missing asset file. See [Audio: the unfinished work](#audio-the-unfinished-work).

Everything else (graphics pipeline, ZigOS, demo framework, ~20 ported cracktro
scenes) is in working shape.

## UPDATE 2026-08-22 — migrated to Zig 0.16, building & running again

- **Toolchain updated 0.10 → 0.16.0** (installed at `~/.local/zig/0.16.0/zig`).
  Migration was mechanical: `@intToFloat`/`@floatToInt`/`@intCast`/`@bitCast`/`@ptrCast`
  two-arg → `@as(T, @newBuiltin(x))`, `@enumToInt`/`@ptrToInt` renames, `@fabs`→`@abs`,
  `for (xs) |x,i|` → `for (xs, 0..) |x,i|`, `&` on array-iteration captures,
  `var`→`const` on never-mutated locals, `build.zig` rewritten for `std.Build`, and
  `JS.zig` Console rewritten off the removed `std.io.Writer` (Writergate) to `bufPrint`.
- **Audio stubbed to silence** — the lost `.smp` embed is gone; `generateAudio()` now
  zero-fills. The exported audio surface (buffers/getters) is intact for the JS side.
  Full audio still needs a rethink (see below).
- **Fixed an unrelated flicker bug**: `docs/css/crt.css` `.overlay` ran a 1ms
  `overlay-anim` strobe whose hidden keyframe got sampled at a random phase each frame,
  blanking every canvas ~20% of frames ("black for a frame, all screens"). Removed.
- **Verified in-browser**: the `dbug` scene renders at ~60fps; channel-switching to the
  prebuilt scenes works. Build: `zig build -Drelease=true -Dwasm`.

### Remaining migration work (not yet done)
Only the `dbug` dependency graph was compiled/verified. The mechanical transform was
applied to *all* `src/*.zig`, but scenes not reachable from `floppy.zig` are **unverified**
and two known 0.16 blockers live in code they pull in:
- **`utils/zalgebra.zig` uses `pub usingnamespace`** — removed in 0.16. Needs manual
  re-export (used by the 3D math path: `dots3d`, some scenes).
- **`std.rand.DefaultPrng`** → renamed to `std.Random.DefaultPrng` (starfields, `demo`,
  `shapes_tester`, `starfield_3D`).
- Before switching `floppy.zig` to another scene, expect to fix that scene's graph
  (mostly the two items above; the mechanical stuff is already applied).
- `docs/wasm/*.wasm` are still the **old prebuilt** binaries — rebuild per-scene once its
  graph compiles.

---

## Build & run

| | |
|---|---|
| Toolchain | **Zig 0.10.x** (this is Zig-0.10 source — `std.build.Builder`, `@intToFloat`, `@ptrCast(T, x)`, `for (xs) \|x, i\|`). It will **not** compile on Zig 0.11+. `zig` is not currently on PATH here. |
| Build | `zig build -Drelease=true -Dwasm` → outputs `docs/bootloader.wasm` |
| Convenience | `build.sh` (builds + serves), `serve.sh` |
| Serve | `cd docs && python3 -m http.server 3333` → open `/` or `/debug.html` |
| Scene selection | Compile-time: edit `src/floppy.zig` to pick which scene the `.wasm` runs (currently `dbug`). The prebuilt per-scene `.wasm` files in `docs/wasm/` were each built with a different `floppy.zig` line. |

**Prebuilt `.wasm` in `docs/wasm/` are stale** relative to source — they were built
before the current (broken) audio state, which is why the live site still runs.

---

## Architecture (one screen)

```
docs/               static web front-end (hand-written, no bundler)
  index.html        entry page; loads loader.js; CRT monitor overlay + 4 canvases
  loader.js         ACTIVE front-end. No audio. window.onload → instantiate wasm → RAF loop
  zigloader.js      NEWER front-end w/ ScriptProcessor audio. ES-module. NOT wired to any HTML.
  wasm-audio-worklet.js   3rd audio attempt (AudioWorklet). NOT wired to anything.
  wasm/*.wasm       one prebuilt binary per scene (stale)

src/
  bootloader.zig    WASM entry. Exposes exported fns to JS (boot/frame/render/audio/...).
                    Owns the physical framebuffer + the ST-style border-opening render loop.
  zigos.zig         "ZigOS": Color, LogicalFB (320x200 indexed), ZigOS (4 planes + palette
                    + HBL handlers), 8x8 system-font text printing.
  floppy.zig        Scene selector (comment/uncomment one `pub const Demo = ...`).
  scenes/*.zig      ~21 demo scenes (ported Atari/Amiga cracktros + tests).
  effects/*.zig     reusable demo effects: scrolltext, star/3D-star fields, bobs,
                    sprites, fade, shapes(tri/line/pixel), background, text, mandelbrot.
  sound/            synth.zig, waveforms.zig  — audio, unfinished (see below).
  utils/            math (mat4/quaternion/zalgebra/zmath), loaders, debug, JS interop.
  assets/           fonts, per-scene screens/palettes.  NOTE: assets/audio/ is MISSING.

tools/*.py          asset preprocessors (PNG→raw/palette, font conversion, sine-gen).
```

### Rendering model (the interesting part)
- 4 **logical** framebuffers: 320×200, each pixel an index into a per-FB 256-entry RGBA palette.
- 1 **physical** framebuffer: 400×280 RGBA (`u32`), i.e. 320×200 visible + borders.
- `renderPhysicalFrameBuffer()` in `bootloader.zig` (lines ~144-408) walks the physical FB
  scanline-by-scanline and emulates **Atari ST border-opening tricks** (top/bottom/left/right
  overscan) driven by per-scanline HBL handlers and a `Resolution.{planes,truecolor}` toggle.
  This is the densest, trickiest code in the repo — tread carefully.
- JS side: per frame `clearPhysicalFrameBuffer()` → `frame(dt)` → for each enabled plane
  `renderPhysicalFrameBuffer(i)` then blit the wasm memory slice into a canvas `ImageData`.

---

## Audio: the unfinished work

There are **three** artefacts from three different approaches, none complete:

1. **`bootloader.zig` `generateAudio()` (lines ~443-469)** — the "basic audio without
   audioworklet" from the last commit (`ae4d23e`). Resamples an embedded sample into
   `sound_left_buffer` on demand. **This is what breaks the build:**
   ```zig
   // bootloader.zig:41
   const wave_b = @embedFile("assets/audio/therehegoes_i8_10026.smp");
   ```
   **`src/assets/audio/` does not exist and the `.smp` was never committed** → `zig build`
   fails at compile time. This is fix #1 for getting back to a green build.

2. **`docs/zigloader.js`** — the matching JS front-end for approach (1). Uses the (deprecated)
   `ScriptProcessorNode` to call `generateAudio()` and pump `getLeftSoundBufferPointer()` to
   the speakers. It's an **ES module** exporting `toggle_sound` etc., but **no HTML loads it** —
   `index.html` and `debug.html` both still `<script src="loader.js">`, and `loader.js` has
   zero audio code. So the audio path is written but never activated.

3. **`docs/wasm-audio-worklet.js` + `src/sound/synth.zig`** — an earlier, more ambitious
   AudioWorklet-based synth (proper off-main-thread audio). `synth.zig` exports `sfxBuffer`
   and `u8ArrayToF32Array` and generates notes from `waveforms.zig` wavetables. But:
   - `synth.zig` is **orphaned** — not imported by `bootloader.zig` (which imports `waveforms`
     but never uses it), so its exports aren't in any built `.wasm`.
   - the worklet's `constructor` never actually receives `zig_machine`/`memory` (all commented
     out, lines 15-19), so `process()` early-returns forever.
   - not wired to any HTML either.

**Recommended path to "audio works again":**
1. Restore/replace the missing sample → get a green build. Either commit a real
   `src/assets/audio/therehegoes_i8_10026.smp`, or swap `@embedFile` for a generated
   buffer using `waveforms.zig` + the `sfxBuffer` logic already written in `synth.zig`.
2. Point `index.html` at `zigloader.js` (as a module) and confirm the `ScriptProcessor`
   path makes sound. That's the shortest route to *any* audio.
3. Only then, if you want it done "properly", finish the AudioWorklet path (approach 3):
   pass `memory` + the wasm exports into the worklet via `processorOptions`, and reuse
   `synth.zig`. This is the real goal implied by the file names.

Decision to make: **ScriptProcessor (simple, deprecated) vs AudioWorklet (correct, more
plumbing)** — see question 3 below.

---

## Known issues / loose ends (beyond audio)

- **Broken build**: missing `.smp` embed (above). Blocks everything.
- **Two front-ends drifting apart**: `loader.js` (active, no audio) vs `zigloader.js`
  (audio, unused). They duplicate the whole render loop and the `list_channels` array —
  any scene/channel change has to be made twice. Worth collapsing to one.
- **`debug.html` calls `main()`**, `index.html` calls `main()` too (Sound button), but
  neither `loader.js` nor `zigloader.js` defines `main()`. Dead onclick handlers.
- **External CDN dependency**: `index.html` pulls `normalize.min.css` from cdnjs — the only
  non-self-contained asset; will break offline.
- **Stale prebuilt binaries**: `docs/wasm/*.wasm` predate current source.
- **Toolchain pin**: nothing records the exact Zig 0.10.x used. A `zig 0.11+` will fail
  with confusing errors. Worth pinning in the README / a `.zigversion`.
- **`floppy.zig` scene switching is compile-time only** — no runtime scene list inside a
  single binary; the "channels" are actually separate `.wasm` files chosen in JS.

---

## Good places to start reading

| I want to… | Read |
|---|---|
| understand the whole data flow | `docs/loader.js` then `src/bootloader.zig` `boot`/`frame`/`renderPhysicalFrameBuffer` |
| understand the graphics model | `src/zigos.zig` (`Color`, `LogicalFB`, `ZigOS`) |
| finish audio | this section + `bootloader.zig:28-54,443-469`, `zigloader.js`, `sound/synth.zig` |
| add/port a scene | any `src/scenes/*.zig` (e.g. `deltaforce.zig`) + `src/effects/*` + `floppy.zig` |
| see the ST border trick | `bootloader.zig:144-408` |

---

## Open questions for Matt

1. **The missing sample** `therehegoes_i8_10026.smp` — do you still have it somewhere
   (it's a raw i8 8-bit sample), or should we drop the embedded-sample approach entirely
   and generate audio from the `synth.zig` wavetables instead?
2. **Which front-end is canonical** — should we retire `loader.js` and make `zigloader.js`
   the one true front-end (and update `index.html`/`debug.html` to load it as a module)?
3. **Audio target** — quickest-path `ScriptProcessorNode` (deprecated but ~working in
   `zigloader.js`), or go straight to the `AudioWorklet` you started (`wasm-audio-worklet.js`
   + `synth.zig`)? The worklet is the "right" answer but needs the memory/exports plumbing finished.
4. **Zig version** — are you OK staying on 0.10.x, or do you want to modernize the whole
   codebase to current Zig (large but mechanical: builtins renamed, `for` capture syntax,
   `build.zig` API rewrite)? That's a fork-in-the-road decision before touching much else.
