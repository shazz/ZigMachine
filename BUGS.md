# Known bugs

Open defects, one entry each. Fixed ones are deleted — the history is in git.

Keep an entry useful: what is wrong, **where**, what the *root cause* is (not
just the symptom), and what a fix would have to do. A bug nobody can act on is
a complaint.

---

## Some `apps/*_headless.mjs` may be missing their `gate` line

Worth a sweep: check whether any OTHER `apps/*_headless.mjs` is missing its
`gate` line. The two found so far were both discovered by accident.

---

## REPLICANTS GARFIELD: two measured divergences from the original

**Where:** `apps/zig/scenes/replicants_garfield.zig` (CODEF 28)
**Found:** the port review, 2026-09-12

Separate from the border fix (2026-09-25: tubes and bars are now colour-0
rasters running into the border) — these are the picture itself not matching
the original.

1. **Gradient wrap.** The port wraps the rasterFont4 stack with `@mod`; the
   original leaves rows outside the 360-row stack CLEARED. Measured: differs on
   17 of 20,000 frames, by up to 11 rows. Root cause is the choice of wrap rule,
   and the two rules are both defensible — a fix has to pick one deliberately and
   re-hash the scene, not silently change it.
2. **`fx.sinx` step rule.** The original accumulates `inc` per row; the port
   multiplies. Mathematically equal until rounding, so it only shows at a pixel
   boundary. This is the float-accumulator-vs-multiply divergence this repo has
   now hit on several ports; a fix means accumulating, and pinning the result
   with a frame hash.

Not moved here, because they are explicit porter's choices rather than defects:
the port's fractional positions snap to whole ST pixels while the browser remake
blends over half a pixel — on this machine, snapping is the authentic behaviour.

---

## `LogicalFB.drawScanline` has three hazards, one of which corrupts memory

**Where:** `libs/zig/zigos.zig:522`
**Found:** the library survey (2026-09-12) and again writing `docs/TUTORIAL.md` (2026-09-13)

```zig
pub fn drawScanline(self: *LogicalFB, x1: u16, x2: u16, y: u16, pal_entry: u8) void {
    if ((x1 < self.fb_w) and (x2 < self.fb_w) and (y < self.fb_h)) {
        const delta = x2 - x1;
```

1. **`x2 - x1` is u16 and wraps when `x2 < x1`**, so the loop runs ~65000 times
   and scribbles past the row. In debug this traps; in ReleaseSmall it silently
   corrupts whatever follows the plane. Root cause: no ordering check on the
   arguments. The cheap fix is `if (x2 <= x1) return;` and it changes no valid
   caller.
2. **End-exclusive**: it paints x1..x2-1, so every caller that thinks
   inclusively loses a pixel per run.
3. **`x2 == fb_w` is DROPPED, not clamped** — the guard is `x2 < self.fb_w` — so
   the function can never draw the last column, and it fails silently rather
   than clipping.

Hazard 1 is a straight fix. Changing 2 or 3 shifts existing callers, so it needs
a before/after framebuffer hash of every scene (`apps/scene_hash.mjs`).

---

## Scene struct field defaults are NEVER applied, so a re-entered scene resumes from stale state

**Where:** `apps/zig/demo_main.zig:37` (`var cart: Cart = undefined;`)
**Found:** the ZigOS trap survey, 2026-09-12

A scene written as `field: T = value` is a lie: `cart` is `undefined`, so the
defaults never run and the struct arrives as raw bytes. It LOOKS correct on a
cold boot only because wasm memory starts zeroed. A scene re-entered from the
menu inherits the PREVIOUS cart's bytes and resumes from that scene's state.

Root cause: the declaration, not the scenes. Every scene is expected to assign
every field in `init()`, which is an unwritten rule the language appears to make
unnecessary. It has already bitten two scenes.

A fix either zeroes or properly initialises `cart` in `demo_main` so the
language's own semantics stop being a trap — note that a blanket
`cart = .{}` would hit the data-segment duplication in the next entry.

---

## `self.* = .{}` on a large struct emits a DUPLICATE data segment

**Where:** `apps/zig/scenes/union_intro.zig:57`, `union/doors.zig:57`,
`union/credits.zig:50`, `union/dragonball.zig:37`, `union/trsi.zig:63`
**Found:** the ZigOS trap survey, 2026-09-12; cost measured at 517 KB on the sampler

Assigning a comptime-known `Demo{}` over a big struct makes the compiler emit
that whole struct as a second initialised data segment, on top of the one the
variable already has. In a 2 MB cart window that is real money — it capped the
sampler once already.

Root cause: `.{}` on a large aggregate is a comptime constant, and the linker
cannot fold it into the existing segment. The fix is field-by-field assignment
in `init()` (`noextra.zig:241` shows the pattern and carries the note).

Related: `= undefined` on a module-scope array is not free either — with
`--import-memory` the linker cannot assume zeroed memory and emits an explicit
zero segment per array. In a scene that weighs one cart; in a library it weighs
EVERY cart (library-owned copper tables cost 16.3 KB/cart until the scene was
given ownership). `libs/zig/` has not been audited for other sizeable
library-owned buffers.

---

## `zg.Sprite` is unusable with a negative y

**Where:** `libs/zig/effects/sprite.zig:154`
**Found:** the library survey, 2026-09-12. Live caller: `ics.zig:145-146`, grid sprite y in [-32, -1]

`render` computes the top clamp correctly at line 142-144, then at line 154 does

```zig
var offset: u16 = left_x_position + ( (@as(u16, @intCast(self.y_position)) + clamped_y_top_position) * screen_width );
```

— casting the raw, still-negative `y_position` AFTER the clamp branch instead of
using the clamped value. Illegal cast in debug, silent garbage in ReleaseSmall.

Root cause: the clamp computes a correction but never substitutes it into the
offset. A fix uses the clamped origin (0 when y < 0) in the offset and keeps
`clamped_y_top_position` purely as the source-row skip.

---

## Three scenes still point a RenderTarget at a buffer on `init()`'s stack

**Where:** `apps/zig/scenes/dbug.zig:117` and `:124`, `ics.zig:105`, `stcs.zig:164`
**Found:** the scene survey, 2026-09-12

```zig
var render_buffer: RenderBuffer = .{ .buffer = &buffer, .width = 50, .height = SCROLL_CHAR_HEIGHT };
self.scroller_target = .{ .render_buffer = &render_buffer };
```

`render_buffer` is a local of `init()`. The `RenderTarget` outlives it, so every
later call reads a view that some other frame's stack has overwritten. It
happens to work while nothing reuses that stack depth, which is why it is not
obvious.

Root cause: the VIEW is on the stack even though the pixels it points at are not.
`bladerunners.zig:102-106`, `deltaforce2.zig:115` and `fallen_angels.zig:85-86`
show the two fixes already used here — make the view a struct field, or put it at
module scope.

---

## `ancool.zig`'s raster HBL tests physical line numbers on a normal plane

**Where:** `apps/zig/scenes/ancool.zig:75-79`
**Found:** the scene survey, 2026-09-12

```zig
if (line > 40 and line < 240 ) { fb.setPaletteEntry(1, rasters_b[(raster_index + line - 40) % 152]); }
if (line > 240) { fb.setPaletteEntry(1, back_color); }
```

Per-plane HBL lines are LOGICAL 0..199 on a normal plane (only the global HBL and
overscan planes are physical 0..279). Testing 40..240 therefore shifts the raster
40 rows down and leaves a stale bottom, because lines 200..240 never arrive.

Root cause: the handler was written against the physical numbering. `fallen_angels`
had the same bug and was fixed by moving to `copper.visible(fb, 0)`, which works
the numbering out per plane — that is the fix here too.

---

## `charpanel.zig` uses `std.debug.assert` as a runtime guard

**Where:** `libs/zig/effects/charpanel.zig:73-75`
**Found:** the library survey, 2026-09-12

```zig
std.debug.assert(cfg.steps.len >= 2 and cfg.steps.len <= MAX_LIVE);
std.debug.assert(cfg.cols * cfg.rows <= 256);
std.debug.assert(cfg.patterns.len % (cfg.cols * cfg.rows) == 0);
```

Carts ship as ReleaseSmall, where `std.debug.assert` compiles to NOTHING. So the
three invariants this config relies on are checked in exactly the build nobody
runs, and a bad config walks straight past them into an out-of-range index.

Root cause: a debug-only assert standing in for validation. Since every field
here is comptime-known at the call sites, the fix is `comptime` assertions (which
fail the build) — or an explicit run-time check that clamps or returns.

---

## `tex.zig` masks palette INDICES bitwise

**Where:** `apps/zig/scenes/tex.zig:278`
**Found:** the scene survey, 2026-09-12

```zig
for (fb.fb[row_start..][0..n], back_b[back_start..][0..n]) |*d, m| d.* &= m;
```

`fb.fb` holds palette indices, not colour bits. ANDing two indices produces a
third index with no relationship to either colour, so the result is whatever
happens to live at that palette slot. It looks plausible only because the
palette was arranged to make it look plausible.

Root cause: the original does this as a bitplane AND, where the operands ARE
colour bits. On an index buffer the equivalent is a keyed blit (`KEY_EN`) or a
lookup, not `&`. The blitter table already proposes `MINTERM = A AND B` for this
site — note that the hardware minterm has the same objection unless the data is
genuinely planar.

REPS OLD (`replicants.zig`) has the same masking and its scroller glyphs are
visibly blocky and garbled with a ghost row below. That one is deliberately kept
as-is for comparison, so it is a TODO (delete it once the comparison is done),
not a bug to fix.

---

## `apps/verify.mjs` fails a CORRECT polyglot cart

**Where:** `apps/verify.mjs:81-86`
**Found:** while porting CODEF 34 to C

The polyglot gate asserts that palette entry 0 is opaque and samples only
`fb.slice(0, 4096)`. Both are assumptions about one specific screen — a
full-screen 320-wide plasma:

* entry 0 is legitimately TRANSPARENT in any layered screen, and
* in a 400-wide overscan buffer the first 4096 bytes are the (black) top border.

So `docs/demo-c-screen34.wasm` reports **FAIL while being correct** — confirmed
by reading the physical framebuffer directly. Any future polyglot cart that is
not a plasma will "fail" the same way, which trains everyone to ignore the gate.

Root cause: the check validates `hello.c`'s SHAPE, not the ABI. A fix needs
shape-independent assertions — non-zero pixels anywhere in the plane's own
geometry, and animation between two frames — rather than fixed offsets.

---

## `check_fits` over-reports free cart RAM

**Where:** `build.sh`'s `check_fits` step
**Found:** during the ZX0 packing pilot

The FITS line counts static size only. It cannot see run-time ZX0 depack
buffers, so it reports headroom a cart does not have: `union_intro` prints
"749 KB free" against roughly 553 KB real.

Root cause: the only sizes available to it are the linked ones. A fix has to
expose unpacked sizes from `packed_assets` and add the largest CONCURRENT depack
buffer per cart — and it wants doing before packing rolls out past the pilot,
because every packed scene widens the error.

---

## Headless "frame cost" reports JIT warm-up, not frame cost

**Where:** the `frame cost:` line in the `apps/*_headless.mjs` harnesses
(e.g. `apps/replicants_garfield_headless.mjs`)
**Found:** 2026-09-12

The timed run starts cold, so the number includes V8 warm-up: ~1.0 ms cold
against 0.2–0.45 ms warm, i.e. the reported cost can be 3x the real one. Anyone
comparing two screens, or a before/after, is comparing warm-up noise.

Root cause: no warm-up pass before the measurement. A fix runs N frames
untimed first and reports a warm best-of-N.

---

## The docs state three things about the machine that are FALSE

**Where:** `docs/ZIGOS_API.md` (header, §3, §7), `docs/HW_API.md:134`
**Found:** writing `docs/TUTORIAL.md`, 2026-09-13

1. `ZIGOS_API.md`'s header points at pre-reorg paths — `zigos/zigos.zig`,
   `zigos/players/mod.zig`, `apps/scenes/music_debug.zig`. None of those exist;
   the library is `libs/zig/zigos.zig`. The BODY of the document is current, which
   makes the header worse, not better: a newcomer fails at step one on a file
   whose contents are otherwise right.
2. `ZIGOS_API.md:49` says to select the active scene in `floppy.zig`, and `:214`
   says the sanctioned way to reach the borders is `setResolution(.truecolor)`.
   Scene selection is `apps/zig/cart.zig` via `cart_opts`, and overscan is
   `setOverscanBuffer()` + `openBorders()`.
3. `HW_API.md:134` documents `hwPhysWidth() u32 // 400`. It returns **800** — the
   doubled raster.

Root cause: the reorg and the overscan model changed under documents nobody
re-read. A fix is mechanical, but (3) especially needs doing: a C or Rust cart
that believes the comment lays out its buffer at half the stride.

**Three more of the same class, found 2026-09-20 rebuilding the guide's UI:**

4. `docs/index.html:67` links `ZIGMACHINE_GUIDE.html#0` — a dead anchor ever
   since the guide moved to real slugs. The front page's own link to the
   reference does not land anywhere.
5. `docs/FLOPPY_DISK.md` still says *"Status: MVP working… Still to do:
   FAT/multi-file, disk-browser menu, block streaming"*. **All three exist.**
   The disk shelf has a FAT, GEM browses it, and block streaming is gated by
   `apps/stream_pacing_check.mjs`. A newcomer reads that and concludes the
   machine cannot do what it demonstrably does.
6. **ZigOS's module-level functions are documented NOWHERE.** `requestSong`,
   `requestSongTune`, `stopSong`, `readBlock`, `audioStreamStart/Feed/Stop`,
   `LinePalette`, `flickerAllHbl` and others are `pub` on the module rather
   than methods on a struct, and both docgen parsers only walk struct methods.
   This is not staleness — it is a whole category of the API that has never
   appeared in the generated reference. Root cause is in
   `tools/docgen/zig_parse.py`: it has no module-level pass at all. The fix is a
   new parse plus a "ZigOS — module functions" section, which is a content
   decision, not a mechanical one.

(4) and (5) are one-line edits. (6) is the real one, and it is the same shape as
the bug that hid 46 library methods behind a nested-struct parse error until the
2026-09-20 rebuild: **the generator silently omits what it cannot parse, so the
page looks complete and is not.** Any fix should make the generator *report* what
it skipped rather than drop it.

---

## The menu clips long screen names in the right column

**Where:** `apps/zig/scenes/menu.zig:82-84`
**Found:** 2026-09-12

Right-column entries start at x = 16 + 152 + 12 = 180. With the 8 px system font
that leaves 17 characters before x = 320. "REPLICANTS GARFIELD" is 19, so it
renders truncated.

Root cause: the column pitch (152) and the text origin were chosen before the
shelf held names this long, and `printText` neither clips nor ellipsises — it
just runs out of screen. A fix either narrows the gutter, uses
`printTextSmall`, or shortens the catalog name; whichever is chosen, it wants a
check that no `catalog.zig` name exceeds the column.

---

## The border keeps the depack effect's colour for one frame too long

**Where:** the `depack_fx` runner and `tuneIn` (`libs/zig/depackers/depack_fx.zig`,
`demo_main`'s tune-in path)
**Found:** the union intro branch, 2026-09-13

After a depack effect or the TV-snow tune-in, the first frame of the real screen
still shows the EFFECT's background in the border. Seen as union_demo's first
street frame being black instead of grey, and as 96,000 border pixels at k=1 in
`demo_main`'s tuneIn (which `polyglot-tunein` mirrors on purpose).

Root cause is ordering, not colour: the host's `hwClear` runs BEFORE the cart's
`frame()`, so the first cart frame is cleared with the background the effect
left behind. Fixing it inside the cart is impossible — it never gets to run
first.

The fix belongs in the effect runner / tuneIn: restore the background on the
LAST effect frame rather than leaving it for the first cart frame. Then update
the harnesses that currently ALLOW the k=1 border diff
(`apps/tunein_check.mjs:203`), or they will go on passing either way.

---

## `zx0pack --manifest` skips by file mtime only

**Where:** `tools/`'s `zx0pack`, `--manifest` mode
**Found:** during the packing pilot

The manifest decides whether to re-pack from the SOURCE file's timestamp. A
line's depack effect or its displayed text can change without the source asset
changing, and the packer then silently keeps the stale `.zx0`.

Root cause: the staleness key covers the input bytes but not the packing
PARAMETERS. The workaround is to remember `--force`; the fix is to hash the
parameters into the manifest key so remembering is not required.

---

## The `rasters` depack effect does not look like the real thing

**Where:** `libs/zig/depackers/depack_fx.zig`, the `rasters` effect
**Found:** 2026-09-13

On highly compressed data (TRSI, packing to 3.8%) it shows a few broad bands
rather than the dense stripes the real Jampack loader produced.

It follows Jampack 4.0's `DEPICE.S` — the packed byte goes to `$FF8240` on each
bit-buffer reload — so the broad bands may be correct for data this small, or may
be a misreading. Two things are assumed rather than read, and either would
produce exactly this: **D7's upper/red byte is assumed 0 (unverified)**, and
colour 0 is sampled once per scanline.

Root cause not established. Resolving it means checking those two assumptions
against the real loader rather than against memory of it.

---

## A stream started while an SNDH is playing mixes the two

**Where:** `apps/zig/demo_audio_main.zig:204` (`audioStreamStart`)
**Found:** following the stale-song-fetch race, 2026-09-14

```zig
export fn audioStreamStart(rate: f32) void {
    mod.stop();
    ym.stop();
```

It stops the MOD and YM players and takes Paula channel 0, but never calls
`sndh.stop()`. An SNDH already running keeps driving the PSG, so both are
audible at once.

Root cause: the function was written before the SNDH player existed and was
never extended when it was added — the same omission shape as the ABI-mirror
entry. The fix is one call; the value is in also checking the other direction.

Unverified and worth checking at the same time: whether a cart SWAP bumps
`songGen` (`docs/sealed-loader.js:1017`). A swap that requests no new song may
leave a late fetch from the OLD cart free to take the chip.

---

## Paula's step is hardcoded to 44100, and a dry ring jumps instead of pausing

**Where:** `machine/sdk/audio.zig:16` (`SAMPLE_RATE: f32 = 44100.0`)
**Found:** 2026-09-13

Two defects in the sealed audio chip, both present today:

1. Paula's playback step is computed from a FIXED 44100, not from the browser's
   actual `audioCtx.sampleRate`. On a device whose context runs at 48000 every
   sample plays at the wrong pitch and the wrong rate, and nothing reports it. No
   one has logged `audioCtx.sampleRate` across browsers to find out how often
   this is wrong.
2. When the stream ring runs dry, playback does not pause — it keeps looping the
   ring, so the listener gets a 2.6 s jump backwards instead of a short silence.

Root cause for (1) is that the constant is baked into the ABI header shared by
the chip and the players, so it cannot be a run-time value without a change on
both sides.

---

## Channel change (+ / −): two behaviours have never been tested

**Where:** `docs/sealed-loader.js` (`swapCart`), the +/− controls in the glass
**Found:** when the TV channel feature landed

* **Sound across a channel change was only ever tested MUTED.** What happens to a
  playing SNDH, or a stream mid-ring, when the cart swaps is unknown — and the
  swap-race hotfix history says this area fails silently rather than loudly.
* **Mobile / touch layout of the +/− buttons is untested.** Nobody has opened it
  on a phone.

Root cause not established for either — they are gaps in testing, not diagnosed
faults. They are here rather than in `TODOS.md` because the behaviour may already
be wrong and we would not know.

---

## B.I.G. DEMO — shared context for the entries below

**Where:** `apps/zig/scenes/big/`
**Moved here:** 2026-09-20, from `TODOS_BIG_DEMO.md` (deleted; its history is in git)

All five screens behind the jukebox are built and gated. Every entry below is a
refinement to something that already RUNS: nothing here is a known-wrong
mechanism, it is all either unread 68000 code or a measured anomaly with no
explanation yet. They are here rather than in `TODOS.md` because each one is a
place where the port may be wrong and nobody can currently prove otherwise.

All five screens behind the jukebox are built and gated. Everything below is a
refinement to something that already runs: **nothing here is a known-wrong
mechanism**, it is all either unread 68000 code or a measured anomaly with no
explanation yet.

Addresses are in the real demo's memory, read by the ShirazMCP session driving
it in an emulator (2026-09-19/20). Reference captures and dumps live in
`prototypes/codef/23/atarimania/` — gitignored, main checkout only.

**The standing division of labour**, which is what made this work: measurements
off the captures on one side, code readings out of the emulator on the other,
and neither side guessing across the boundary. Every one of the eight
corrections either session made this round was found because the *other* one
had an independent source.

---

---

## B.I.G. DEMO key 1 (Colorright) — the band's colour never walks the pen range

**Where:** `apps/zig/scenes/big/`

### The selector at $14780 — the one VISIBLE gap
Thirteen dispatch arms write the 15-line rainbow band's colour into thirteen
*different* palette entries, so the band's colour walks across the pen range.

    read   $1439C   move.w $14780(pc),d1      the HBL dispatch
    write  $146EE   addi.w #$1,$14780
    read   $146F6   cmpi.w #$d,$14780         wraps 12 -> 0 at $14702

**It is gated on the flag at $14788**, which the VBL sets when the sweep counter
bottoms out at 3 — so it advances ONCE PER FULL SWEEP: 3 -> 180 -> 3 is 354
frames, 7.08 s. Thirteen pens is about **92 seconds for the full walk**.

Jump table at **$147AA** (not $147AC — `lea` has one extension word and is
right; only `movem.l (d16,PC)` is off by two on this demo):

    $143AC $143BC $143F2 $14426 $14458 $14488 $144B6
    $144E2 $1450C $1453A $1456C $145A2 $145DC

Two arms are read: `$143AC` writes entry 0, `$143BC` writes entry 4. **Eleven
are unknown.** The port drives pen 0 always, which is right for the first seven
seconds of a visit and wrong after — see `big/key1.zig`.

### The star validity test at $14118 — and a real anomaly
Placement is rejection-sampled and all three constants are confirmed in the
bitmap: y rejects >$98 then +$17 (range 23..175), x masks to EVEN and rejects
>$E7 then +$2C (range 44..274), pen rejects <= 3. Stars ACCUMULATE — 5,656
shared between consecutive frames with ZERO removed, and every one still
present 400 frames later.

$14118 decides whether a candidate is valid and is **not read**. The port
rejects an already-occupied pixel, inferred from the fill rate falling as the
field fills, not from code.

**The anomaly:** of the 116 even columns in 44..274, exactly ONE never holds a
star — **x = 44** — while x = 46 carries roughly double the mean (50 against
26). That is what you would see if d0 = 0 were remapped to 2 rather than
rejected. 26 expected occurrences and 0 observed is not sampling noise.

### Two more per-sweep mechanisms, gated on the same flag
* `$1470E` walks $14782..$14786 with `eori.w #$ffff,(a0)+` — three words
  toggled, with an early exit on `tst.w d0 / bne`. A small state machine, one
  step per sweep.
* `$1472A` decrements $1477C and reloads it from $1477E (live: 3 and 4), so it
  fires every FOURTH sweep, about every 28 s, and runs $1473E..$14758: an
  8-word RING at **$147F4** rotated by one word.

Neither is implemented and neither has a known visible effect.

---

---

## B.I.G. DEMO key B — the font-to-buffer renderer is unread

**Where:** `apps/zig/scenes/big/`

### The font-to-buffer renderer — the only unread piece
Font ink lives in planes 0..2 as a glyph-set SELECTOR (byte `b` picks plane
`b div 30`, cell `b mod 30`); screen ink lives in plane 3 as the tint layer.
Something in between transposes one to the other, and it has not been read.

Everything it feeds IS known: eight pre-shifted buffers at $D326 onward
($D3BA $D43A $D4BA $D53A $D5BA $D63A $D6BA $D73A, stride $80 = 64 words = one
word per band line), the 8-phase counter at $D322 dispatching through $D356,
the coarse shift at $D164, and the copy at $D1F0 (160 bytes a line, 64 lines,
`addq.l #$6` so it touches plane 3 and nothing else).

### How 32 px is divided between the coarse shift and the buffers
The rate is settled — **4 px a frame**, measured: $D328 advances ONE byte per
8-phase cycle (+1 over 8 frames, +8 over 64, read twice), and a byte is one
32-px cell. But the coarse 16-px shift at $D164 is reached from SIX of the
eight phases, not one, and 6 x 16 reconciles with nothing anyone has proposed.
The port does not need to know; a future change to the scroll does.

Note the routine READS two bytes and ADVANCES one — $D32A and $D330 are the
current cell and the NEXT, a sliding window across a 32-px boundary.

---

---

## B.I.G. DEMO key 2 — cannot be made byte-exact (for the record)

**Where:** `apps/zig/scenes/big/`

**Complete, and it cannot be made byte-exact.** The generator at $18F44 is
seeded from the 200 Hz clock at $4BA and the live beam position at $FF8206, so
two runs of the REAL demo do not produce the same plane. What is reproduced is
the structure, and the harness checks statistics rather than pixels.

For the record, in case anyone re-derives it: the diagonal shift IS a closed
rotation — `movem.l (a1),d2-d7` at **$18B36** saves twelve words of the head
*before* the loop and **$18B98** writes them at the far end after it, eleven
verbatim and the twelfth replaced by the fed value.

---

---

## B.I.G. DEMO key 3 — the three scroll scripts' targets are a shape argument

**Where:** `apps/zig/scenes/big/`

**Complete.** One thing is a shape argument rather than a reading: the three
scroll scripts at $1B778, $1B7AA and $1B7C8 are real $FFFF-terminated
(count, reload) data at the addresses the other three sections load, but that
they drive a2, R1 and R2 *respectively* has not been confirmed. Flagged in
`big/key3_data.zig`.

---

---

## B.I.G. DEMO audio — the STE DMA sound chip has never played a tune

**Where:** `apps/zig/scenes/big/`

The STE DMA sound chip is implemented (`libs/zig/players/ste_dma.zig`) and
**untested against a tune that actually uses it** — the Digital Department's
five `FLAG~ay` tunes write to it zero times, being STF-style arrangements that
drive digidrums through PSG volume writes. `audioDmaWrites()` / `audioDmaStarts()`
report the traffic, so an idle chip is visible rather than assumed.

Not emulated, and named in the source: the frame-end interrupt (MFP GPIP 7),
the Microwire volume and tone registers, and the real chip's latching of the
pointers at the END of a frame rather than when the go bit is set.

A cookie jar is planted at $5A0 (`_MCH` = STE, `_SND` = YM + DMA). It made no
difference to these five and is kept because a tune that probes and finds
nothing takes a different path silently.

---

---

## B.I.G. DEMO — two things that will bite whoever picks this up

**Where:** `apps/zig/scenes/big/`

**Anchors are per-screen.** `capture row = display line + N`, and N is NOT the
same across captures — the menu is +31, key 1 is +30. Pin it per capture (the
reliable way is correlating the bitmap's horizontal edges against the still)
before comparing anything.

**A documented gap still ships a wrong screen.** Both bugs Matt found by eye —
key 1 standing still, key 2's field dying to eight colours — were in code
whose comments said "not read, guessed". The comment was not the problem; the
missing thing was a CHECK that the gap changes something observable. Every
structural assertion stayed green through both: a palette of eight colours is
still per-line, a frozen palette is still the right shape.
