# Session Handoff

**Date:** 2026-09-12
**Branch:** `main` (still never pushed — now ~160 commits ahead of origin)
**Author:** matt-grain (+ Claude), alongside a parallel "sc68" session

> **Read `zigmachine-fable-audit` in the project memory first.** It is the
> authoritative record of the two Fable audits, what was fixed, and the concrete
> next steps. This file is the session-shaped view of the same ground.

## What Was Done

**Phase 2 is complete.** GEM is a ROM chip: its own `rom.wasm`, its own RAM
window, a flat ABI, and a C program that draws real GEM widgets through it. Then
two Fable audits went over the result and three of their four workstreams landed.

### The arc, in order

1. **`f726646` — one line was costing 517 KB.** `self.* = .{}` in
   `gem_desktop.zig` needed a comptime-known `Demo{}`, which embedded ST Replay's
   sample buffer — so the linker emitted a SECOND 526 KB blob of zeros. That, not
   GEM, was capping the sampler. `MAX_PCM` is 1 MB now; a 773,120-byte sample
   loads and plays.
2. **`c686aaf` — the disks got a recipe.** `tools/mkdisks.sh` repacks every
   `.zmd` from the built carts; `apps/disk_check.mjs` mounts each image and
   *instantiates* its cart against the host's real `env`. This closed the oldest
   standing blocker and earned its keep within the hour.
3. **`976092d`→`758483f` — Phase 2 steps 2.0–2.3.** ROM window at
   `[0x500000,0x700000)` (HW 1.3.0), flat ABI, `rom.wasm`, the desktop moved into
   the chip, and launching became a host-side cart swap — GEM runs a program off
   the floppy, the way TOS does. That also killed the launch double-click leak.
4. **`ecf5cc2` — a C program calls GEM.** Writing the caller proved the polyglot
   claim FALSE as it stood: `guiOpen` took flat `u32`s whose *meaning* was "you
   must be a Zig program". Hence `guiOpenPlane`.
5. **`4320881`, `49e9b54`** — merged and verified the sc68 session's SNDH/68000
   work, then landed their audio reset (Escape used to leave the previous tune
   playing).
6. **`714e00a` — MED OVERSCAN is back.** The sealed machine could always do it;
   only a deleted ZigOS helper was missing.
7. **`90cb85c`→`7c1792f` — acting on the audits.** See the memory.

### Decisions made

- **Each screen defines how to leave; the host binds no keys.** Matt's call. The
  loader ate Escape globally, so no screen could bind it. Now forwarded, and
  `demo_main.zig` decides. Carts may declare `ownsKeyboard`.
- **The machine reclaims a program's resources; the host does not remember them.**
  `romReset()` and `machineAudioReset()` on every cart instantiation. A program
  cannot free what it holds when the host replaces it — it is already gone.
- **A context is opened by naming a PLANE, never a pointer.** One ABI shape,
  callable from any language.
- **The 200-line rule does not apply to Zig here** (in `CLAUDE.md`).
- `decisions.md` now exists — 8 ADRs, backfilled.

## Current State

- **Working tree:** clean *of my work*. ~39 uncommitted files belong to the
  **sc68 session** (new scenes `supplex_fs2`, `noextra`, `replicants_dd2`, the
  CODEF tooling). Do not `git add -A` — stage by name. We have both swept each
  other's work by accident today.
- **Gate:** green. `./build.sh` → 33 disks repacked and instantiating, 9 native
  test files, five harnesses (`verify`, `rom_abi_check`, `gem_headless`,
  `sndh_headless`, `dbug_headless`).
- **Build:** `./build.sh`, not `zig build`. **Serve:** `./serve.sh`, not
  `python -m http.server`.

## Blockers & Open Questions

- [ ] **The repo has never been pushed.** ~160 commits ahead of origin.
- [ ] **Two sessions share one checkout.** sc68's worktree is gone, so both of us
      edit `main` directly. Stage by name; split a file by hunk if both touched it.
- [ ] **Rust calls no ROM entry point** — Phase 2's criterion 3 is C-only.
- [ ] **2.4 parked by Matt**: the replay-frequency question (should loading snap
      the rate to the sample's own, which needs the rate stored in the FAT's spare
      bytes?) and spending ST Replay's remaining 603 KB.

## Next Session

### Recommended starting point

**Split `rom/gem/desktop/desktop.zig` (1162 lines)** — step 4 of the audit work,
the only one not done. Proposed: `dirmodel.zig` (disk_dir + folders + sort — pure
and testable, like `namefield`/`deskinf` already are), `dirview.zig` (View, rows,
`drawDir`, `dirHitAt`), `deskmenu.zig`, `deskanim.zig`; `desktop.zig` keeps
`render`.

It hides a real bug worth fixing first, cheaply: **`runDialogs` ORs six modal
flags but omits `copy.active`**, so the menu bar is not locked while the COPY
dialog is up.

### Planned work

1. Split `desktop.zig` (+ the `copy.active` bug).
2. Export windows and menus — needs an **event model**
   (`guiWindowOpen/Content/Event` + `guiClip`), not more entry points. `Wm`'s
   `takeClosed`/`takeZoom` are already the right one-shot shape.
3. The host findings nobody has acted on: the loader BUILDS GEM's floppy
   directory; the `.zmd` FAT is parsed twice; the boot beep is a YM tune sequenced
   in JavaScript; the stream ring's write cursor lives in JS.
4. Move `filesel.zig` / `namefield.zig` from `desktop/` to `gui/` — they are app
   widgets, and the ABI exports them.

### Context to load

**Must read:**
- Memory `zigmachine-fable-audit` — the audits, what is done, what is next.
- `decisions.md` — why the machine is shaped this way.
- `rom/sdk/rom.zig` + `rom/rom_main.zig` — the ABI header and the chip.
- `docs/PHASE2_ROM_CHIP.md` — annotated where its own claims were wrong.

**Helpful background:**
- Memories `zigmachine-browser-testing-traps` (a HIDDEN Chrome tab stops
  `requestAnimationFrame` and fakes convincing bugs), `zigmachine-disk-recipe`,
  `zigmachine-keyboard-ownership`, `zigmachine-cart-ram-window`.
- `apps/gem_headless.mjs` — it is a HOST now, not just a driver; trust it over
  the browser.

**Harness artifacts:** none active.

---
*Generated by `/handoff` — for team members without conversation history*
