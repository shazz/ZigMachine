# Session Handoff

**Date:** 2026-09-06 (evening)
**Branch:** feat/effects-menu
**Author:** matt-grain

## What Was Done

The **UNION INTRO is now the full Union experience end-to-end**: `trsi → wab →
placement → main(doors)` as one continuous flow, driveable on a phone, with the
effect-fidelity fixes Matt spotted while testing live. Plus a real host bug fix
(stale planes leaking over the menu).

### Commits (this session)
- `7bb4642` **union intro: chain into main screen + effect-fidelity fixes**
- `5d8ef5d` **sealed-loader: touch gamepad, wasm cache-bust, clear disabled plane canvases**
- `3673272` **union intro: wire placement (efmain_intro) into the intro SEQ**

### Key Changes
- **Placement wired into the intro** (`3673272`) — added `placement` to
  `union_intro.zig`'s `Active` union + SEQ; committed the previously-untracked
  `union/placement{,_strips}.zig` + assets + `tools/union_intro_assets.py`.
- **Intro → main chaining** (`union_intro.zig`, `7bb4642`) — `union_intro.Demo`
  now runs the SEQ then flows straight into `doors.Doors` (the main screen).
  Placement literally assembles the main-screen image, so the hand-off is
  seamless. ESC during the intro OR on the main screen bubbles `wants_quit` to
  the menu (same contract menu.zig uses for the standalone UNION MAIN entry).
  New forwards: `input`/`setShadeMode`/`pollSong` while `in_main`.
- **TRSI entry acceleration** (`trsi.zig`) — was a constant-speed lerp (every
  tile drifted a fixed 60 frames). Now faithful to `codef_animatedtiles.js`:
  every tile arrives at `ENDVBL (=60)`, so late-starting tiles get a bigger
  per-frame step and visibly **accelerate into place**, snapping together at 60.
  `ENTRY_END` 115 → 60. Logo **fade-out sped up** `ALPHA_INCR` 0.005 → 0.02
  (Matt's call; JS base is 0.005).
- **Scroller lead-in** (`scroller.zig`) — 5 → 13 leading spaces. `scrolltext2`
  primes all `NUM_SLOTS` across the visible strip at init, so the text needs a
  full strip of blanks to **enter from the right edge** instead of appearing
  mid-screen.
- **Door-name title removed** (`doors.zig`) — its fade wasn't well synced to the
  door. `pickTitle` still tracks the enterable door (`self.titled`) so **Space
  still enters the door in front**; names will return as **tiles below the door**
  (Matt's follow-up).
- **Touch gamepad** (`sealed-loader.js`) — on-screen D-pad + Fire + Esc wired to
  the same `demo.input()` codes as keydown, so the whole thing is driveable on a
  phone with no keyboard. D-pad repeats while held (hold-Left slowdown works).
- **Cache-bust** (`sealed-loader.js` + `sealed.html`) — every wasm fetch gets
  `?t=<load-time>`; loader `<script>` is `?v=4`. A rebuilt `demo.wasm`/loader is
  now always picked up on reload instead of the browser serving the stale blob.
- **Plane-canvas clear bug FIXED** (`sealed-loader.js`) — the render loop only
  ever painted an *enabled* plane, so a multi-plane scene returning to the menu
  left its stale layers composited on top ("leftover logos over the menu"). Now
  a plane going dark has its canvas cleared once. Verified in-browser: menu is
  clean after MUSIC DEBUG → ESC. Fixes any scene→fewer-planes transition.

### Decisions Made
- **UNION INTRO chains into the main screen** rather than stopping; UNION MAIN
  stays as the direct-to-main shortcut. Rationale: placement assembles the main
  image, so intro→main is the authentic Union flow.
- **Door title removed, not fixed** — Matt will replace it with name tiles
  *below* the door (better than a floating credits-font label whose fade was
  hard to sync to the door's motion).
- **Fade rate is a tunable, not a port constant** — bumped past the JS 0.005 on
  the author's live judgement.

## Current State

### Branch Status
- Build: `zig build -Drelease=true -Dwasm` **clean** (EXIT=0). `demo.wasm`
  1,904,168 B — fits the 2 MiB window (~193 KB headroom).
- Line caps OK: `doors.zig` 197, `union_intro.zig` 93, `trsi.zig` 160.
- **Uncommitted (pre-existing, NOT this session):** the big `assets/ →
  apps/assets/` relocation (D old / ?? new) + `assets/bugs/` — left as-is, as at
  session start. `HANDOFF.md` is the only file this session leaves modified.
- Local server running on `0.0.0.0:8123` (a pre-existing instance).

### Validated
- **In-browser (desktop):** plane-clear fix (menu clean after a multi-plane
  scene), touch gamepad renders + drives the menu.
- **Live on Matt's phone:** the full intro→entrance→main flow, which is how Matt
  produced the fidelity feedback below.
- ⚠️ Desktop *end-to-end* replay of the intro was inconclusive — Chrome throttles
  rAF in the unfocused automation tab, so screenshots froze mid-animation. Not a
  code issue; the phone run is the real validation.

## Blockers & Open Questions
- [ ] **Entrance ghost trail still MISSING** (Matt's "in the entrance the good
      effect is missing / Ghost"). The original `efmain_intro.js` (lines 161-165)
      draws the runner with a **4-copy x-zoom ghost trail** (x-8/-16/-18/-26,
      alpha 0.7/0.5/0.3/0.1, x-zoom 1.2→1.5). `placement.zig` blits only the solid
      sprite. NOT done this session — it needs the runner on its **own alpha
      plane** (like the main screen's `runner.zig` GHOST_CX/Z/A technique), since
      placement composites everything onto one indexed plane 0 with no per-pixel
      alpha. See Next Session.

## Next Session

### Recommended Starting Point
**Add the entrance ghost trail to `placement.zig`**, mirroring `runner.zig`'s
`blitStretch` + dimmed-alpha-palette ghost (GHOST_CX/GHOST_Z/GHOST_A), fed by the
JS spec in `efmain_intro.js:161-165`. Likely means promoting the runner strip to
its own plane so alpha compositing works.

### Also Matt-owned (his follow-ups)
- Tune the **scroller** text / spacing.
- Add **name tiles below the doors** (replacing the removed floating title).
- **A new idea for next session** — Matt has one he's excited about; ask him.

### Context to Load
**Must read:**
- `apps/scenes/union/placement.zig` — where the ghost trail goes.
- `apps/scenes/union/runner.zig` — the ghost technique to reuse (alpha palette).
- `apps/scenes/union_intro.zig` — the intro→main chaining.
- `apps/scenes/union/doors.zig` — title removed; `pickTitle`/`titled` gate entry.

**Helpful background:**
- `assets/oldies/UnionDemoCracktro/intro/efmain_intro.js` (ghost spec 161-165),
  `lib/codef_animatedtiles.js` (tile motion), `eflogo.js` (fade).
- `docs/sealed-loader.js` — touch pad, cache-bust, plane-clear loop.

---
*Generated by `/handoff` — for team members without conversation history*
