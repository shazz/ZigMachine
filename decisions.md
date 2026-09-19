# Architecture Decision Records

Non-trivial technical choices and *why*, newest first. The rule of thumb: if a
future reader would ask "why did they do it this way?", it belongs here. Routine
choices that follow an established pattern do not.

Backfilled on 2026-09-12 for the ROM-chip work; entries before that date are
reconstructed from the commits that made them, so they are shorter.

---

## 2026-09-19 — Overscan + hardware scroll needed no machine change

**Status:** accepted

**Context:** The AUTOMATION 442 port (CODEF screen 420) wants a tiled background
that pans across the *whole* 400×280 overscan window with zero per-pixel work per
frame. The two capabilities existed separately — `FB_MODE = 2` (SCROLL) pans a
bigger-than-screen buffer, `FB_MODE = 4` (OVERSCAN) draws the border bands — and
the obvious move was a fifth render mode combining them.

**Decision:** No new mode, and no change to `machine/video.zig`.
`renderPlaneOverscan()` already reads its buffer as `lfb(fb_id)` (i.e. through
`FB_BASE`, the pan point) with `fbStride(fb_id)` as the row pitch, so an OVERSCAN
plane bound to a larger buffer with `FB_STRIDE = buf_w` pans correctly the moment
`setScroll()` rewrites `FB_BASE`. The only thing missing was an SDK entry point:
`LogicalFB.setOverscanScrollPlane(buf_w, buf_h)` in `libs/zig/zigos.zig`, which is
`setOverscanBuffer()` with `setScrollPlane()`'s allocation and stride.

**Alternatives considered:** a `FB_MODE = 5` "overscan scroll" render path (more
machine surface, an ABI-visible constant, and a duplicate of a loop that already
did the right thing); or painting the pan per frame into a 400×280 overscan buffer
(112k pixel writes per frame — exactly the cost the hardware scroll exists to avoid).

**Consequences:** No register layout changed, so no ABI rebuild. The one asymmetry
is that `renderPlaneOverscan()` does not re-read `HSCROLL` per scanline, so this
mode has coarse scroll only — a scene wanting per-line distortion still needs
`FB_MODE = 2` and closed borders. Documented in `docs/HW_API.md` §3.

---

## 2026-09-12 — The ROM's ABI names a PLANE, not a pointer

**Status:** accepted

**Context:** The machine/rom split claims a ROM is "just a module linked against
the HW ABI, so any language can call it". The first flat ABI (`guiOpen(os_ptr,
fb_ptr, w, h)`) passed only `u32`s and therefore *looked* language-agnostic. It
was not: those numbers are the addresses of the caller's `ZigOS` and `LogicalFB`,
so their meaning is "you must be a Zig program that links ZigOS". A C app has
neither — it writes palette indices straight into the video region. Nothing caught
this because nothing had ever written the caller.

**Decision:** Entry points a non-Zig app needs take a **plane number**.
`guiOpenPlane(plane, w, h)` and `romInstallPalettePlane(plane)` let the ROM read
that plane's framebuffer base and stride out of the sealed video registers itself,
and lend its own `ZigOS` for text (`ZigOS.initTextOnly()` binds the fonts and
touches no hardware). `guiOpen` stays for Zig callers.

**Alternatives considered:** Exporting ZigOS's layout so C could build the structs
— couples every app to an internal layout. Having the app pass a raw framebuffer
address — plausible, but `FB_BASE` is moved by ZigOS's VRAM allocator, so the
register is the only correct source and the ROM can read it without being told.

**Consequences:** The polyglot claim is now testable and tested
(`apps/verify.mjs` reads the framebuffer back and requires GEM's own output).
`romInstallPalettePlane` is not a convenience: GEM draws in palette *indices*, so
a caller with its own palette gets correct pixels in the wrong colours — a plasma
rainbow renders a GEM panel solid red. An ABI can be technically satisfied and
practically useless.

---

## 2026-09-12 — The machine reclaims a program's resources; the host does not remember them

**Status:** accepted

**Context:** Launching became a host-side cart swap, so a program is torn down and
replaced. Twice this produced the same silent failure: the outgoing program cannot
release what it holds, because by the time anything notices, it is gone. ROM
handles stayed marked used until the tables filled and every call became a no-op
(an app that draws perfectly whose dialogs never appear). Music kept playing over
the next screen.

**Decision:** Reclamation is the machine's job, invoked on every cart
instantiation: `romReset()` for the ROM's handle tables, `machineAudioReset()` (via
the cart-level `audioReset()`) for the sound chip. Neither names a player or a
handle kind.

**Alternatives considered:** The host remembering which player/handles were live
and sending matching stops — that design is what produced the bug, and it needs a
new case for every new resource type. (It had already failed once: `audioSndhStop`
was exported but had no message case in the worklet, so it was unreachable.)

**Consequences:** A new player type or handle kind is covered without touching the
host. Both are guarded by tests that fail when the reset is stubbed out.

---

## 2026-09-12 — GEM is its own wasm module, in its own RAM window

**Status:** accepted · plan in `docs/PHASE2_ROM_CHIP.md`

**Context:** GEM was a Zig module every cart linked statically, so the toolkit
existed once per cart and `gem_desktop.zig` embedded the app it launched — every
app GEM could start was inside GEM's binary.

**Decision:** `rom.wasm`, linked against `machine/sdk/` like a cart, with its own
2 MiB window at `[0x500000, 0x700000)` **above** the video region. The host
instantiates machine → rom → cart. Apps import the named module `rom_sdk` (a
header of `extern` declarations) and never `rom`.

**Alternatives considered:** Carving the ROM window out of the cart's 2 MiB —
defeats the purpose, since the point is that an app's RAM stays the app's.

**Consequences:** `SHARED_PAGES` 79 → 112, which is a **breaking change for every
cart ever packed** (a cart declares the imported memory's max and refuses a larger
one). That is why `tools/mkdisks.sh` had to exist first. The `Rect`/`BLACK`/`WHITE`
constants are now *defined* in the header rather than re-exported from
`rom/gem/gui/types.zig` — a header that imported the toolkit would drag it back
into every app — so those two definitions must be kept in step by hand.

**Note on the original motivation, which was wrong:** this was planned to reclaim
RAM. `gem.Desktop` is 2332 bytes. What actually capped ST Replay's sample buffer
was a duplicated data segment (see below). The real value delivered is the
polyglot ABI and that the desktop no longer contains its apps.

---

## 2026-09-12 — The machine answers "how much RAM is left?" (HW 1.2.0)

**Status:** accepted

**Context:** A cart's window is shared by its statics, its stack, and everything
it links. Running past the top does **not** trap — it writes into the video region
and the machine dies later, somewhere unrelated. Buffer sizes were guesses.

**Decision:** Sealed instructions `hwRamBase/Top/Size/Used/Free`, backed by
`REG_CART_HIGH`. The machine cannot know a cart's high-water (the linker bakes it
in), so the **host** measures it from the wasm and declares it via
`hwSetCartHigh` — which keeps the instruction language-agnostic. `hwRamFree()`
reports 0 when undeclared, deliberately indistinguishable from "full": an unknown
window must read as *take nothing*.

**Consequences:** One measurement routine (`docs/wasm_hiwater.js`) is shared by
the loader and the checkers, so the hardware and the tools agree to the byte. Each
module is measured against **its own** map — the audio thread's window is half the
size at the same address, and measuring it against the video map would let a cart
grow a megabyte into song RAM unnoticed.

---

## 2026-09-12 — Each screen defines how to leave; the host does not bind keys

**Status:** accepted

**Context:** The loader interpreted Escape globally (skip boot, then back to the
menu) and returned before `demo.key()` ever saw it, so no screen could bind it —
ST Replay's "Esc = stop" rebooted the machine instead. Space/Enter, WASD and 1-7
had the same shape, and in an application W both wiped and moved a selection.

**Decision:** The host forwards keys and the machine decides. `demo_main.zig`
routes Escape: the boot ROM skips while it is up, a cart that handles keys owns
it, a plain scene cart falls back to the menu. A cart may declare `ownsKeyboard`
to stop the host interpreting the rest.

**Consequences:** Carts that declare nothing keep the old behaviour, so no packed
disk changed.

---

## 2026-09-12 — `.zmd` disks are built by a recipe, and verified offline

**Status:** accepted

**Context:** The disks were build output nobody could rebuild. They drifted a week
behind the wasm and froze an import list the host no longer had, so every disk
failed to instantiate — recoverable only by reading the images back.

**Decision:** `tools/mkdisks.sh` repacks them from the built carts, deriving the
list from `docs/demo-*.wasm` and repacking only what is stale.
`apps/disk_check.mjs` mounts every image and **instantiates** its cart against the
host's real `env`. Both run from `build.sh`.

**Consequences:** A host ABI change is caught offline in one command instead of as
a black screen. The env object is an ABI: a retired import becomes a documented
no-op stub, never a deletion.

---

## 2026-09-06 — Four ownership areas (`machine`/`rom`/`libs`/`apps`)

**Status:** accepted · see `docs/HARDWARE_SPEC.md` §12 and each area's README

**Decision:** Split the tree by who owns the code, with cross-area imports going
through **named modules** (`@import("zigos")`, `@import("rom")`,
`@import("hardware")`) rather than relative paths.

**Consequences:** Named modules are path-independent, which is why the reorg
barely touched imports. A file may belong to only one module, so a module that
needs another area's code must import it by name — this is what forced `rom_sdk`
to reach GEM through `@import("rom")` rather than `../gem/`.

---

## 2026-08-22 — Seal the hardware behind a memory-mapped ABI

**Status:** accepted · design in `docs/HARDWARE_SPEC.md`

**Decision:** The machine is sealed wasm modules that coders receive as binaries
plus header files (`machine/sdk/`); everything crosses through a fixed memory map
and a small set of entry points. "You get the memory map, not the schematics."

**Consequences:** The constraint *is* the console — and because the seal is a wasm
ABI rather than a Zig API, apps in any language sit on it.
