# Phase 2 — cutting GEM into its own ROM chip (`rom.wasm`)

**Status:** planned, not started. Written 2026-09-12, after HW 1.2.0 gave the
machine `hwRamFree()` and the numbers below stopped being guesses.

## Why

**Not for RAM.** That was the original reason and it turned out to be wrong:
`gem.Desktop` measures **2332 bytes**. What capped ST Replay's sample buffer at
512 KB was one line in `apps/zig/scenes/gem_desktop.zig` — `self.* = .{}`, whose
comptime-known `Demo{}` embedded the 526 KB sample buffer, so the linker emitted a
second 526 KB blob of zeros as its own data segment. Removing it gave 517 KB back
and the megabyte fits (commit that follows `690b2c3`). Ask `hwRamFree()` before
believing any story about where a cart's window went.

What remains, and is reason enough:

1. **The polyglot claim is untested.** `rom/README.md` says a ROM is "just a
   module linked against the HW ABI", so **a C or Rust app should be able to call
   the Zig GEM ROM**. It cannot today — the seam is a Zig API (`@import("rom")`),
   not a wasm ABI. That is the whole point of the machine/rom split and nothing
   currently exercises it.
2. **The desktop is a cart that CONTAINS its apps.** `gem_desktop.zig` embeds
   `st_replay.App` outright, so every app GEM can launch is linked into GEM's own
   binary. That does not scale past one app, and it is why the launch
   double-click leaks into the newly-launched app (HANDOFF blocker).
3. **RAM, secondarily.** Once several apps exist, linking them all into the
   desktop puts every app's buffers in one window again — the duplicate-blob bug
   was the acute form of a chronic shape.

For reference, the window as it stands (`node apps/check_fits.mjs docs/demo-*.wasm`):

| cart | used | free |
|---|---|---|
| `demo.wasm` (menu, no GEM) | 419 KB | 1629 KB |
| `demo-st_replay.wasm` | 1447 KB | 601 KB |
| `demo-gem.wasm` | 1454 KB | 594 KB |

Most of both is now the 1 MB sample buffer, as it should be.

## The shape of the change

Four wasm modules become five, sharing one `WebAssembly.Memory`:

```
machine-video.wasm   [0x000000..0x100000)   sealed HW
rom.wasm             NEW window             GEM: desktop + GUI toolkit
demo-*.wasm          [0x100000..0x300000)   the app — now ALL of it is the app's
                     [0x300000..~0x4DC000)  video region (shared, unchanged)
```

**Give the ROM its own window above the video region** rather than carving it out
of the app's: `SHARED_PAGES` 79 → ~111 (~5.2 MiB → ~7.3 MiB of one shared
memory). Shrinking the app window would defeat the entire point.

Because it is ONE linear memory, a pointer the app passes is directly readable by
the ROM — strings and structs cross as `(ptr, len)` with no copy, and GEM keeps
drawing straight into the framebuffers in the video region.

## Steps

Ordered so each one is separately buildable and testable. **2.1 is the
de-risking step**: change the call *shape* first, the module boundary second.

### 2.0 — carve the window ✅ DONE (HW 1.3.0)
- `machine/sdk/memmap.zig`: `ROM_RAM_BASE` / `ROM_RAM_TOP`, bump `SHARED_PAGES`.
- Extend the RAM instructions: `hwRomRamFree()` / `hwRomRamUsed()`, a second
  `REG_ROM_HIGH`, declared by the host the same way (`docs/wasm_hiwater.js`
  already measures any module).
- ABI change → **clean-rebuild both wasm modules** (`.zig-cache` too).
- *Done:* `ROM_RAM_BASE/TOP` = `[0x500000, 0x700000)`, `SHARED_PAGES` 79 → 112,
  `REG_ROM_HIGH` at 0x60, and `hwRomRam{Base,Top,Size,Used,Free}` +
  `hwSetRomHigh`. `ram_check` covers both windows, including that they do not
  alias and both survive `hwInit`.
- **The breakage was real and is worth remembering:** growing the shared memory
  invalidated every packed cart (a cart refuses a memory bigger than its declared
  max), including the C and Rust ones, whose `build.sh` carried the page count as
  a literal. `disk_check` caught all 28 offline in one command. This is exactly
  why `tools/mkdisks.sh` had to land first — step 2.3 changes the host `env` and
  will do the same thing again.

### 2.1 — a flat ABI, still statically linked ✅ DONE
- `rom/sdk/rom.zig`: the app-facing ABI as `extern fn` declarations only —
  **handles, not pointers**: `romWindowOpen(...) u32`, `romDesktopFrame(dt) void`,
  `romText(handle, ptr, len, x, y) void`, … Only i32/f32 cross.
- Callbacks the other way (the ROM asking the app to do something) route through
  the host as integers, exactly like `env.hblDispatch` already does:
  `env.romDispatch(id, a, b, c)`.
- Behind it, a shim that still calls today's Zig API in-process.
- Migrate the five call sites (`gem_desktop.zig`, `st_replay{,_ui,_draw}.zig`) off
  `@import("rom").gui` / `.gem` onto the flat calls.
- *Done:* `rom/sdk/rom.zig` is the ABI, published as the named module `rom_sdk`.
  ST Replay (`st_replay{,_ui,_draw}.zig`) no longer imports `rom` at all — it
  holds `u32` handles and every call passes only numbers. Identical on screen,
  verified in-browser end to end (panel, ITEM SELECTOR, 773120-byte load).
  `gem_desktop.zig` is deliberately NOT migrated: it *becomes* the ROM at 2.3, so
  it keeps using the internals.
- **What the exercise was for, and it paid immediately.** Two things only showed
  up by changing the call shape:
  1. `st_replay_draw.zig` reached THROUGH the context — `g.blit.fill(g.fb, …)` —
     for the waveform spans. Across a module boundary that is impossible, because
     the ROM's code and the app's are different binaries. It is now `guiFill`, a
     verb of its own. The app also stopped owning a `Blitter` for the toolkit's
     benefit: the ROM brings its own.
  2. **Handles need a lifecycle.** ST Replay re-opened its Gui/Dialog/FileSel on
     every launch without closing them, so after two launches the ROM's tables
     were exhausted and every call silently became a no-op — the app still drew,
     but the ITEM SELECTOR stopped opening. Guarded now by the `rom-handle-reuse`
     scenario, which launches the app 4 times (> table size) and asserts the
     selector still responds. Verified to fail without the fix.
  The tables are deliberately tiny for exactly that reason: a leak has to surface
  in seconds, not on someone's fifth window.

### 2.2 — build `rom.wasm` ✅ DONE
- `build.zig`: a real `addExecutable` for `rom/rom.zig`, `import_memory`,
  `global_base = ROM_RAM_BASE`, its own stack.
- Loader: instantiate `machine → rom → app`; wire the ROM's imports to the
  machine's exports (it links `machine/sdk/` directly), and the app's `env` to
  the ROM's exports.
- Delete `rom_mod` from every cart's imports. The shim becomes the real thing.
- *Done:* `rom/rom_main.zig` is the chip (27 exports, 9.8 KB), `rom/sdk/rom.zig`
  is now a pure header of `extern` declarations that imports NOTHING from `rom` —
  an app linking GEM's internals is a layering mistake the build no longer allows.
  The host instantiates **machine → rom → app**, each importing only from the ones
  before it, and an app's `env` gets the ROM's exports spread in (`...rom`), so a
  new entry point needs no host change.

  `rom.wasm` imports exactly three things: `memory`, `hwVideoBase`, `hwBlit`. It
  sits in its own window at 258 KB used / 1789 KB free, and `hwRomRamFree()`
  reports it. `ram_check` asserts the chip fits its window, that the hardware
  agrees to the byte, and that the cart ends below `ROM_RAM_BASE`.
- **The cart window barely moved (593 → 595 KB free), and that is expected.**
  `gem_desktop.zig` still statically links GEM for the *desktop*, so the toolkit
  exists twice right now — once in `rom.wasm` for apps, once in the cart for the
  desktop. Step 2.3 deletes the second copy; until then the win is architectural,
  not spatial.
- Two things that had to be settled to make the header pure: `Rect`, `BLACK` and
  `WHITE` are now DEFINED in the header rather than re-exported from
  `rom/gem/gui/types.zig` (a header that imported the toolkit would drag it back
  into every app) — they are part of the ABI now, like a register offset, and the
  two definitions must be kept in step by hand.

### 2.3 — the desktop stops being a cart that contains apps
- `gem_desktop.zig` embedding `st_replay.App` has to go: the desktop lives in
  `rom.wasm`, and launching an app means the **host** instantiating that app's
  cart into the app window — the in-place swap the menu already does
  (`pollCartRequest` / `getCartTagPtr`). GEM gains the same request path.
- This also closes the HANDOFF blocker *"the launch double-click leaks into the
  newly-launched app"*: a fresh instantiation cannot inherit a pointer state.
- **Land `tools/mkdisks.sh` first.** Every `.zmd` freezes its cart's import list
  at pack time, and this step changes it. Regenerating disks must be a command,
  not an archaeology exercise (see HANDOFF's first blocker).

### 2.4 — spend the RAM
- Re-measure with `node apps/check_fits.mjs docs/demo-*.wasm`, then raise
  ST Replay's `MAX_PCM` against the real `hwRamFree()`, not a constant.
- Answer the replay-frequency question while the sample path is open.

## Acceptance criteria

1. `demo-gem.wasm`'s window usage drops by ≥ 400 KB; `hwRamFree()` reports it and
   the panel shows it.
2. `node apps/{ram_check,check_fits,verify,gem_headless}.mjs` all pass, and
   `build.sh`'s gate still fails a cart that overruns its window.
3. **`apps/verify.mjs` proves a C or Rust app calling a ROM entry point** — that
   is the whole claim of the machine/rom split, and it is currently untested.
4. The host `env` object gains names but loses none (a retired import becomes a
   documented no-op stub — `4c00b19` is why).
5. `rom/README.md`, `docs/HW_API.md` and `docs/HARDWARE_SPEC.md §12` stop
   describing Phase 2 in the future tense; `decisions.md` gets an ADR for the
   window layout and the handle-based ABI.

## Risks

- **The flat ABI is a real API design, not a mechanical port.** GEM's surface is
  windows, dialogs, menus, icons, a file selector. Getting it wrong in 2.1 is
  cheap; getting it wrong in 2.2 is not. Keep it small — what ST Replay and the
  desktop actually use, nothing speculative.
- **Register-offset overlaps are silent.** Any ABI offset change means a clean
  rebuild of *both* sealed modules, or two modules disagree about the map.
- **`.zmd` disks freeze imports.** Nothing in 2.0–2.2 should change the app's
  `env` surface; 2.3 will, and needs the disk recipe in place first.
- ZigOS gets statically linked into both `rom.wasm` and the app. Code
  duplication, not RAM duplication — acceptable, but worth an ADR line.
