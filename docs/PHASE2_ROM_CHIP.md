# Phase 2 — cutting GEM into its own ROM chip (`rom.wasm`)

**Status:** planned, not started. Written 2026-09-12, after HW 1.2.0 gave the
machine `hwRamFree()` and the numbers below stopped being guesses.

## Why

A cart's RAM window is `[0x100000, 0x300000)` — 2 MiB — and *everything the cart
statically links* lives in it. GEM is statically linked (`build.zig`: "rom/ …
Statically linked into the demo for now"), and `apps/zig/scenes/gem_desktop.zig`
goes further: it embeds `st_replay.App` outright. So `demo-gem.wasm` is the
desktop **plus** the sampler **plus** the boot ROM, sharing one window:

| cart | used | free |
|---|---|---|
| `demo.wasm` (menu, no GEM) | 419 KB | 1629 KB |
| `demo-st_replay.wasm` | 935 KB | 1113 KB |
| **`demo-gem.wasm`** | **1456 KB** | **592 KB** |

That 592 KB is why the sampler is capped at a 512 KB buffer: a 1 MB one ran past
the top of the window, which does not trap — it corrupts the video region, and
the machine died later inside `skipBoot()` (`56de690`). GEM's own contribution is
roughly **525 KB** (1456 − 419 menu baseline − 512 sample buffer). Moving it out
is the only way ST Replay gets near the ~1.9 MB the real thing reports.

The second reason is the promise in `rom/README.md`: a ROM is "just a module
linked against the HW ABI", so **a C or Rust app should be able to call the Zig
GEM ROM**. It cannot today — the seam is a Zig API, not a wasm ABI.

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

### 2.0 — carve the window
- `machine/sdk/memmap.zig`: `ROM_RAM_BASE` / `ROM_RAM_TOP`, bump `SHARED_PAGES`.
- Extend the RAM instructions: `hwRomRamFree()` / `hwRomRamUsed()`, a second
  `REG_ROM_HIGH`, declared by the host the same way (`docs/wasm_hiwater.js`
  already measures any module).
- ABI change → **clean-rebuild both wasm modules** (`.zig-cache` too).
- *Done when:* everything still runs and `apps/ram_check.mjs` covers the ROM
  window as well as the cart's.

### 2.1 — a flat ABI, still statically linked
- `rom/sdk/rom.zig`: the app-facing ABI as `extern fn` declarations only —
  **handles, not pointers**: `romWindowOpen(...) u32`, `romDesktopFrame(dt) void`,
  `romText(handle, ptr, len, x, y) void`, … Only i32/f32 cross.
- Callbacks the other way (the ROM asking the app to do something) route through
  the host as integers, exactly like `env.hblDispatch` already does:
  `env.romDispatch(id, a, b, c)`.
- Behind it, a shim that still calls today's Zig API in-process.
- Migrate the five call sites (`gem_desktop.zig`, `st_replay{,_ui,_draw}.zig`) off
  `@import("rom").gui` / `.gem` onto the flat calls.
- *Done when:* the desktop and ST Replay behave identically with zero module
  boundary crossed yet — `apps/gem_headless.mjs` is the judge.

### 2.2 — build `rom.wasm`
- `build.zig`: a real `addExecutable` for `rom/rom.zig`, `import_memory`,
  `global_base = ROM_RAM_BASE`, its own stack.
- Loader: instantiate `machine → rom → app`; wire the ROM's imports to the
  machine's exports (it links `machine/sdk/` directly), and the app's `env` to
  the ROM's exports.
- Delete `rom_mod` from every cart's imports. The shim becomes the real thing.
- *Done when:* `demo-gem.wasm` drops by ~525 KB and `hwRamFree()` says so.

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
