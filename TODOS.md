# TODOS

Things the port/review/library agents found or approximated on 2026-09-12 that
were not shown on screen at the time. The ZigOS effects backlog and the
incidental bugs in older scenes are tracked separately in `docs/DEPACK.md`.

## Decisions for Matt

- [ ] **`LogicalFB.drawScanline`** (`libs/zig/zigos.zig`), three hazards:
  1. `x2 - x1` is u16 and wraps when x2 < x1 → the loop scribbles past the row in
     ReleaseSmall. Recommended now: `if (x2 <= x1) return;`.
  2. End-exclusive: paints x1..x2-1, so inclusive callers lose a pixel per run.
  3. Drops (does not clamp) a run with `x2 == fb_w`.
  Changing 2/3 shifts existing callers — needs a before/after hash of every scene.
- [ ] **`check_fits` blind spot**: it cannot see run-time ZX0 depack buffers, so
  the FITS line OVER-reports headroom (union_intro: "749 KB free", ~553 KB real).
  Expose unpacked sizes from `packed_assets` and add the largest concurrent
  buffer per cart — before packing rolls out past the pilot.
- [ ] **Channel order**: `docs/channels.json` follows the menu (alphabetical).
  Legacy was a hand list; flip `ORDER` in `tools/channels.py` for build order.
- [ ] **Old `replicants.zig` / `reps4/`** kept as REPS OLD for comparison —
  delete once the comparison is done.

## Screens

### replicants_garfield (CODEF 28)
- [ ] Gradient wrap: the port wraps the rasterFont4 stack with `@mod`; the original
  leaves rows outside the 360-row stack cleared. Differs on 17 of 20,000 frames,
  up to 11 rows. Pick one.
- [ ] `fx.sinx` accumulates `inc` per row; the port multiplies. Only matters at a
  pixel boundary.
- [ ] Fractional positions (bars, logo window, sine, scroll) snap to whole ST
  pixels; the browser remake blends over half a pixel.

### ulm_spoon_distorter (CODEF 287)
- [ ] Audio: the original's default is `you.xm`; the port plays the you-low.wav
  sample resampled to 12517 Hz. Same timing — does it sound close enough?
- [ ] No 2x canvas blur (the port is sharp); the clock starts at the first `dt`
  instead of `new Date()`, so the bounce is not phase-locked to sound-on.

### cuddly_starwars (CODEF 360)
- [ ] Music is `Bangkok_Knights.sndh` (the .ym header says "Bankok Knights —
  Hippel after Hubbard"; the file was misnamed "Star-Wars"). Confirm by ear;
  `Lowe_Dave/Bangkok_Knights.sndh` (3 subtunes) is the alternative.
- [ ] Sprites drawn at the nearest pixel; the original smooths sub-pixel
  positions.
- [ ] Stars over the flashing logo use a `cover >= 0.5` rule (porter's choice,
  only during the 39 fade frames); star positions come from a seeded RNG.

### REPS OLD (`replicants.zig`, kept as-is on purpose)
- [ ] No music (never requested one).
- [ ] Scroller glyphs blocky/garbled with a ghost row below — its own
  `fb & mask` index masking.
- [ ] Normal-plane HBL tests physical lines (raster offset 40 rows).
- [ ] 4 planes: cart 0.26 ms + planes 0.30 ms — expect it slower in the browser.
- [ ] Menu re-launch after the init() reset fix not tested in-browser.

### Menu
- [ ] "REPLICANTS GARFIELD" is clipped to "REPLICANTS GARFIEL" in the right
  column.

## TV channels (+ / −)

- [ ] Sound behaviour during a channel change is untested (tested muted).
- [ ] Mobile / touch layout of the +/− buttons untested.
- [ ] No YM hiss with the snow (would need the audio worklet).

## ZX0 packing & depack effects

- [ ] `rasters` effect on highly compressed data (TRSI, 3.8%) shows a few broad
  bands, not dense stripes. Follows Jampack 4.0 `DEPICE.S` (packed byte →
  $FF8240 on each bit-buffer reload); D7's upper/red byte assumed 0 (unverified);
  colour 0 is sampled once per scanline. Check against memory of the real thing.
- [ ] `noise` depack effect ignores progress (tvnoise has no time input).
- [ ] Roll packed assets out scene by scene (only union_intro uses them); keep
  `smp/music1`, `smp/music2`, `screens/df2/rasterbars.raw` unpacked (they grow).
- [ ] `zx0pack --manifest` skips by file time only — run with `--force` after
  changing a line's fx or text.
- [ ] Packer is a near-optimal (salvador-style) parse, not the exhaustive ZX0
  reference; upkr/Shrinkler only worth it if ~15% more is needed.

## Tooling

- [ ] `apps/replicants_garfield_headless.mjs` never creates its default output
  dir (ENOENT without an argument).
- [ ] Headless harness "frame cost" includes JIT warm-up (~1.0 ms cold vs
  0.2–0.45 ms warm) — report warm best-of-N.
- [ ] `cuddly_starwars.zig`: `blitScrollGlyph` indexes per pixel and `update`
  recomputes `STAR_Z_SPEED * 0.1` — unmeasurable, left alone.

## Gate coverage (found while porting screen 34 to C)

- [ ] **`apps/verify.mjs` only validates `hello.c`'s SHAPE, not the ABI.** It
      requires palette entry 0 to be opaque and samples only the first 4096 bytes
      of the plane. Both are assumptions about a full-screen 320-wide plasma:
      entry 0 is legitimately TRANSPARENT in any layered screen, and in a 400-wide
      overscan buffer the first 4096 bytes are the (black) top border. So
      `docs/demo-c-screen34.wasm` reports FAIL while being correct — verified by
      reading the physical framebuffer directly. Any future polyglot cart that is
      not a plasma will "fail" the polyglot gate. Needs shape-independent checks
      (e.g. non-zero pixels anywhere in the plane's own geometry, and animation).
- [ ] **`./build.sh` runs no per-scene harnesses** — only verify / gem / sndh /
      dbug. A scene's own headless harness must be run by hand, so "the gate is
      green" does not mean a scene was exercised. Either register scene harnesses
      or say so in the gate output.
- [ ] **One broken scene fails EVERY cart.** `cart.zig` compiles every scene into
      every cart, so a single compile error blocks all sessions' gate runs (it
      happened twice today, in both directions). Worth considering whether a cart
      can compile only its own scene.

## ZigOS traps worth fixing at the source, not documenting around

- [ ] **A scene's struct field defaults are NEVER applied.** `demo_main.zig` holds
      `var cart: Cart = undefined`, so `field: T = value` is a lie and the struct
      arrives as zero bytes. It appears to work on a cold boot only because wasm
      memory starts zeroed; a scene RE-ENTERED from the menu inherits the previous
      cart's bytes and resumes from stale state. Every scene must assign every
      field in `init()`. This has already bitten two scenes. Consider zeroing (or
      properly initialising) `cart` in `demo_main` so the language's own semantics
      stop being a trap.
- [ ] **`zg.Sprite` is unusable with a negative y** — `Sprite.render` does
      `@intCast(self.y_position)` AFTER its top-clamp branch: illegal cast in
      debug, silent garbage in ReleaseSmall.
- [ ] **Module-scope arrays are not free and `= undefined` costs the same as
      zeros.** With `--import-memory` the linker cannot assume zeroed memory and
      emits an explicit zero data segment per array. In a scene that weighs one
      cart; in a library it weighs EVERY cart (library-owned copper tables cost
      16.3 KB/cart until the scene was given ownership). Audit `libs/zig/` for
      sizeable library-owned buffers.

## Host / ABI mirrors

- [ ] **Audit for other hand-maintained ABI mirrors.**
      `docs/audio-worklet-sealed.js` built the audio cart's imports from a
      hand-written list of machine exports. Adding ONE export to the sealed chip
      (`machineAudioReset`) without updating that list made `demo-audio.wasm` fail
      to LINK, which presents as "audio is gone" with no build error anywhere. Now
      fixed by spreading every `machine*` export by prefix — the way
      `apps/sndh_headless.mjs` always did, which is exactly why the gate stayed
      green while the browser was silent. Anywhere else that lists ABI names by
      hand has the same failure mode.
- [ ] **`apps/dbug_headless.mjs`'s `shot()` comment claims it composites every
      plane. It does not** — `hwRenderPlane(p)` reuses one physical buffer per
      plane, so the PPM holds only the LAST plane rendered. Copying it for a
      multi-plane scene yields a near-black image and wrong conclusions. It also
      crops to 320x200, hiding all overscan content.

## Asset tooling

- [ ] **`tools/convert_png.py` only accepts P/PA-mode PNGs**, so it fails on
      essentially every CODEF asset (they are RGB/RGBA). Every port has had to
      write its own indexer. Worth shipping the quantise-and-reserve-index-0
      pre-pass as a tool (`tools/reps5_assets.py` and `tools/c34_assets.py` are
      two working models). Note it also stamps alpha 255 on all 256 entries in P
      mode, so transparency always has to be re-established in the scene.
- [ ] The transparent field in a CODEF asset has **no fixed polarity** — all four
      combinations have now been seen (alpha-0 black, opaque black, opaque chroma
      green at index 0 via tRNS, and a white field at alpha 0 with black ink).
      Any shared indexer must measure it rather than assume.

## C port (CODEF 34, `apps/c/scenes/screen34.c`)

- [ ] The logo's top row or two may sit under the CRT bezel. `LAYOUT_Y` is a named
      constant for exactly this; a value of ~4 would clear it.
- [ ] The scrolltext is a short credits line naming Mad Vision / Maxi / NoNameNo,
      not the original's message (that is in `prototypes/codef/34/screen.js`).
- [ ] Polyglot carts are reachable only via `?demo=demo-c-screen34.wasm` — they
      are not in the menu or the channel list, since they have no `.zmd`. Worth
      deciding whether they should be.

## Docs

- [ ] `docs/ZIGOS_API.md`'s header still points at pre-reorg paths
      (`zigos/zigos.zig`, `apps/scenes/music_debug.zig`). The body is current.

## Publishing (github.com/shazz/ZigMachine — already public since 2023-02-12)

Corrected: this is NOT a first public push. `origin/main` has been public since
2023 and already carries 268 screen assets (ripped demo artwork, plus the CODEF
`code.js` sources). The push adds 166 commits.

- [ ] **The one genuinely NEW category is music**: `docs/music/` has 0 files on
      `origin/main` and 24 locally (SNDH, `.ymraw`, `.raw`). Artwork exposure is
      an established precedent; audio is not yet. Worth a deliberate nod rather
      than a discovery.
- [ ] **`prototypes/` must stay gitignored** — it holds the 337 MB SNDH archive
      and the CODEF mirror. Correct right now; that ignore is load-bearing.
- [ ] **Add a CREDITS file** naming, per screen, the original demo and its coders,
      graphicians and musicians, plus the CODEF remake author (CODEF itself is
      MIT). Every scene header already carries this; it is collected nowhere a
      visitor to the Pages site would find it. This is the cheap thing that makes
      the whole shelf clearly a tribute with attribution.
