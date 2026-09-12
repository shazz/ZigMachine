# Session Handoff

**Date:** 2026-09-12
**Branch:** `main` (**130 commits ahead of origin — still never pushed**)
**Author:** matt-grain (+ Claude)

## What Was Done

A long GEM-fidelity session driven by live testing, then a rebuild of ST Replay,
then an architectural refactor moving sample loading off the JS loader and into
the machine.

### Commits (13, newest first)
- `HEAD`    **fix: 1 MB sample buffer overran the cart window; tolerant host env**
- `4c00b19` **fix: retiring a host import broke every disk ever packed**
- `0edf4b5` ST Replay: stop really stops; sampler gets 1 MB of RAM
- `5c96816` fix: GEM saw an empty drive after ST Replay dropped its sample buffer
- `c431cce` **refactor: the machine loads and plays its own samples**
- `faead6d` ST Replay: fix Replay/space regressions, silence the buffer at init
- `4eafaff` ST Replay: real time axis, real byte counts, keyboard + mouse selection
- `5345d7d` **ST Replay: rebuild as the real full-screen panel, not a GEM window**
- `43409ef` GEM: measure icon ART, frame scroll gutters, separators + NEW FOLDER
- `a3ea6af` GEM: window geometry memory, icons on the grid, Save Desktop
- `c52c5a0` GEM: clip window text per CHARACTER, not per field
- `ca8a94c` GEM: grey window-scoped File items when no window is selected
- `e391cb6` GEM: Desktop Info in the TOS layout
- `2958a05` **GEM: clipped text, GEM ghosts, real scrolling + TOS dialog fidelity**

### Key Changes

**Root cause behind a whole class of GEM bugs:** `printText`/`printTextSmall` in
ZigOS wrote into the framebuffer with no bounds check, so a window dragged past
the right edge WRAPPED its title and icon labels onto the next scanline. Both are
now one clipped, signed-coordinate glyph blit (which also dropped an off-by-one
leading column), and every direct pixel write in the GUI goes through a clipped
`Gui.plot`. Text also clips per CHARACTER at window edges (`Gui.textIn` /
`textSmallIn`), so scrolling trims a name letter by letter instead of dropping it.

**GEM desktop:** dotted drag ghosts (single "hat" contour, tracing the icon's ART
via `Icon.artBox` — the ripped sheet left TRASH 51px wide for ~25px of art);
window move/resize as ghosts committed on release, and only if the pointer moved;
real scrolling (arrow gadgets, draggable sliders, frozen icon grid so resize
scrolls instead of re-wrapping); per-directory window geometry memory; desktop
icons on the 72x40 cell grid; `Options > Save Desktop` writing `DESKTOP.INF`;
TOS-accurate INFORMATION / NEW FOLDER / trash-alert dialogs; caret editing.

**ST Replay rebuilt** from a windowed GEM app into the real full-screen 640x200
panel, geometry measured off a screenshot of the 3.01 screen and recorded in
`st_replay_ui.zig`. Every binding row is also a button carrying its key's
codepoint, so mouse and keyboard dispatch through one handler.

**The big refactor** (`c431cce`): the JS loader used to fetch samples over HTTP,
downsample them, and replay them from a URL — the host doing the machine's job.
Now `libs/zig/disk.zig` parses the FAT and streams a file into RAM through the
drive ABI a block at a time; ST Replay builds its own display view and feeds the
audio ring itself at rate/60 bytes a frame. The loader lost 2.8 KB and imports
only memory, console, video, the drive, and the audio ring.

### Decisions Made

- **The loader is "glass and speaker".** All real processing belongs in wasm.
  Matt's call, and the refactor above implements it.
  - Rejected: keeping host-side decoding for convenience.
- **The host `env` object is an ABI.** Retired imports stay as documented no-op
  stubs, never deletions — a `.zmd` freezes its cart's imports at pack time.
  - Context: deleting three names froze every disk on the shelf.
- **ST Replay does not reproduce the original's copyright line.** It's a
  reimplementation, so it names itself and credits the original.
- **`DESKTOP.INF` follows TOS's line prefixes but is not byte-compatible** —
  each line carries only what the desktop actually knows, rather than inventing
  field packing we can't back.

## Current State

- Working tree clean apart from this file.
- Build green: `~/.local/bin/zig build -Drelease=true -Dwasm`.
- **18 native tests pass** — `zig test` on `libs/zig/disk.zig`,
  `rom/gem/desktop/{namefield,stamp,deskinf}.zig`, `rom/gem/gui/grid.zig`.
- Polyglot ABI check green: `node apps/verify.mjs` (C + Rust).
- Loader at `?v=24` — **hard-reload (Ctrl+Shift+R) after every rebuild**.
- No harness artifacts active.

### New this session
- `apps/gem_headless.mjs` — boots the sealed machine + demo-gem exactly as
  `sealed-loader.js` does and drives multi-frame pointer gestures. This closes
  the old "automation collapses a drag into one frame" blocker: icon drags,
  window resizes and scrolling are now reproducible without a browser.
- `libs/zig/disk.zig`, `rom/gem/desktop/{namefield,stamp,deskinf,filesel}.zig`,
  `apps/zig/scenes/st_replay_{ui,draw}.zig`.

## Blockers & Open Questions

- [ ] **`.zmd` disks are stale build output with no recipe.** `build.sh` only
      runs `zig build`; nothing regenerates the disks, so they date from
      2026-09-07 and drift behind the wasm. This is the ROOT CAUSE of the boot
      freeze fixed in `4c00b19` and it will bite again. Metadata is recoverable
      (title = scene tag; `demo-st_replay.zmd` carries `SAMPLE.RAW`,
      `demo-stream.zmd` carries `MICROMIX.RAW`) — but the exact per-disk
      `tools/mkdisk.py` arguments need confirming before shipping regenerated
      images. **Wants a `tools/mkdisks.sh` wired into `build.sh`.**
- [ ] **"Replay frequency should map the real sample frequency"** — unresolved,
      two readings. A headerless `.raw` carries no rate. Either f1..f6 just need
      to APPLY the selected rate (they verifiably do), or loading should snap the
      highlighted row to the sample's own recording rate — which needs the rate
      stored on disk. There are 7 spare bytes in each 32-byte FAT entry, so
      `mkdisk.py` could write it and the machine read it, defaulting to no-snap
      on older disks. **Matt to pick.**
- [ ] `DESKTOP.INF` and in-memory folders do not survive a reboot: the host
      injects a read-only FAT and the `.zmd` sits on an HTTP server. Persisting
      needs a host-side decision (a localStorage overlay is the obvious one).
- [ ] The launch double-click leaks into the newly-launched app (it selected f4
      in a headless ST Replay run). Same class as the desktop double-click/drag
      issue already handled.
- [ ] **Sample RAM ceiling is unmeasured.** The buffer is 512 KB. 1 MB overran
      the cart window ([0x100000,0x300000) also holds the 384 KB stack and every
      static in GEM + the boot ROM) and the machine trapped in `skipBoot` — which
      is what "GEM doesn't appear / menu stuck" was. Raising it means MEASURING
      the real ceiling (data-segment end vs 0x300000), not guessing again. The
      real ST Replay reports 1963200 bytes on a 2 MB machine.

## Next Session

### Recommended Starting Point
**Wire the ITEM SELECTOR into ST Replay's `L` key.** `rom/gem/desktop/filesel.zig`
is written, committed and measured off `prototypes/bugs/filesel.png`, but it is
imported by nothing — it is inert. Point "Load from disc" at it and fill it from
the real disk FAT via `libs/zig/disk.zig`, replacing the hardcoded `FILES` array
so the dialog lists what is actually on the disk.

### Planned Work
1. Wire `filesel.zig` into ST Replay; list the real FAT.
2. Add `tools/mkdisks.sh` + wire into `build.sh`; regenerate the stale disks.
3. Answer the replay-frequency question, then implement it.
4. ST Replay editor ops (Mark / Copy / Overlay / Fade in-out / move up-down) —
   bound and clickable, but they don't touch the sample buffer yet.
5. **D-BUG screen credits effects** (text change, character effects) —
   reference: `https://wab.com/screen.php?screen=556`. Requested, not started.

### Context to Load

**Must read:**
- `apps/zig/scenes/st_replay.zig` + `st_replay_ui.zig` + `st_replay_draw.zig` —
  state / geometry / drawing, split three ways for the file-size budget.
- `libs/zig/disk.zig` — the machine's own FAT reader; how a file gets loaded now.
- `rom/gem/desktop/filesel.zig` — the selector waiting to be wired up.
- `docs/sealed-loader.js` — what the host is still allowed to do (and the
  no-op stub comment explaining why retired imports stay).

**Helpful background:**
- `apps/gem_headless.mjs` — how to verify any of this without a browser.
- Memory `zigmachine-gem-browser-testing`, `zigmachine-workflow-cache`.
- `docs/FLOPPY_DISK.md` — v1/v2 disk layouts that `disk.zig` parses.

**Harness artifacts:** none active.

---
*Generated by `/handoff` — for team members without conversation history*
