# Bad patterns: what makes a cart slow or wrong, and the fix

Every pattern here has cost a real cart frames on KESTREL (the FPGA board) or a wrong picture,
and most are flagged by a tool. Measure before fixing:

- `node apps/frame_cost.mjs <tag> --budget` estimates a frame: the cart's cycles plus FRESCO's
  passes over its planes, and lists every misaligned site with its file:line.
- `tools/perf_audit.sh <tag>` ranks the waste. The finding names in `code` below are its own.
  Details are in [PERF_AUDIT.md](PERF_AUDIT.md).
- `fpga/tools/board_fps.py` and the OSD (F11, Shift+F11) read the board itself.

The board's 60 fps frame is ~1.67 Mc (100 MHz). A store costs ~2.3 cycles, a palette write the
same, a misaligned access ~210, a CHISEL blit ~800 fixed, an f32 add/mul 9-10, an f64 divide
~560, and every enabled plane ~0.4-0.6 Mc of compositing. A cart drops below 60 between ~1.75
and 2.1 Mc estimated.

## 1. Planes

### One plane per effect
**Error:** starfield on plane 0, logo on plane 1, scroller on plane 2, "because it was easy".
**Why it costs:** FRESCO composes every enabled plane over the whole screen: ~0.4 Mc a plane.
With 3 planes the cart has ~0.4 Mc left, with 4 nothing.
**Fix:** painter's order in ONE plane: one clear (or dirty erase), then draw back to front, with
colour indices remapped into one palette. Keep a second plane only for a hardware-scrolled or
offset layer, an HBL that races the beam (border opening, mid-screen split), or more than 256
colours in total.
**Seen:** ancool 3 → 1, supplex_fs2 3 → 1 (30 → 60 fps), fallen_angels 3 → 1, tcb_colorshock 2 → 1.

### A plane that never changes
**Error:** a static background plane left enabled and redrawn, or an empty plane left on.
**Detect:** `static_plane`.
**Fix:** draw it once; disable planes nobody sees.

## 2. Writing what is already there

### Redrawing the static page every frame
**Error:**
```zig
pub fn render(self: *Scene) void {
    @memset(fb, 0);                 // clears 64 KB...
    drawLogo(fb);                   // ...to redraw the same logo
    drawText(fb, self.page);        // ...and the same page of text
    drawScroller(fb, self.x);       // only this moved
}
```
**Detect:** `redundant_store`, `clear_then_redraw`.
**Fix:** "only modify what needs to be modified" (Matt). Draw static things once at init; each
frame erase only what moved (its last rectangle) and redraw only that. Keep the last state and
redraw a text cell only when it changed.
**Seen:** big_demo's jukebox (cart 0.92 → 0.36 Mc), skystrike's hall of fame, union_reps' still
picture, mentalhangover.

### Rewriting a colour register with its own value
**Error:** an HBL or a raster loop that writes all 16 colours every line.
**Detect:** `palette_rewrite`.
**Fix:** write only the entries that change (the ST coder's rule: budget CHANGES, not entries).

### Scrolling by rewriting the rows
**Error:** shifting a band of the framebuffer by k pixels with the CPU every frame.
**Detect:** `scroll_band`.
**Fix:** pan instead: HSCROLL / FB_BASE (`setScrollPlane`, `setOverscanScrollPlane`), then draw only
the new column.

## 3. Alignment

### Misaligned loads and stores
**Error:** a u16/u32 read from a byte table or an `@embedFile` at an odd offset, a `packed`
struct, `std.mem.readInt` on unaligned data in a hot loop.
**Why it costs:** the board's CPU traps on a misaligned access: ~210 cycles each instead of 1.
**Detect:** perf_audit's misaligned count, frame_cost's MISALIGNED section (file:line).
**Fix:** `align(4)` on the table or the embedded file, an aligned copy made once at init, or read
the bytes one by one. `zg.mem` allocations are ≥ 4-aligned since 24 Oct.
**Seen:** ics 8 → 60 fps (~12 K traps a frame), naos (~23 K), union_superscroller 1,571 → 8 a
frame; 57 carts fixed in the 24 Oct sweep.

### memcpy from a misaligned source
**Error:** `@memcpy(dst, src)` where `src` and `dst` disagree mod 4 (e.g. a picture embedded with
no alignment, copied into an aligned buffer every frame).
**Why it costs:** the board's memcpy then builds every word from four byte loads: +9 cycles a word.
**Detect:** `misaligned_memcpy`.
**Fix:** align the source like the destination (`align(4)` / `align(8)` on the buffer or the
`@embedFile` copy).
**Seen:** big_demo copied 70 KB a frame this way (~0.1 Mc on the board); replicants_garfield 0.14 Mc.

## 4. Maths

### Float per frame
**Error:** `f32`/`f64` maths in update, render, an HBL handler, or per pixel/row/vertex;
`std.math.sin` a frame; CODEF's JavaScript doubles copied as they are.
**Why it costs:** f64 is soft-float (a divide ~560 cycles); f32 is 9-21 cycles on the FPU carts only.
**Fix:** integers, fixed point (Q16.16, Q14), sine tables (`zg.fixtrig`, 1024 steps), incremental
steps. Build tables at COMPILE time (a `comptime` block evaluates the original's float maths
exactly). Float is fine at init and in the `_f32` twin carts.
**Seen:** polkadots 2 → 28 fps; gen4, tlb_spoon, noextra, union_intro, music moved to fixed point.

### A float accumulator "exactly periodic"
**Error:** `angle += 0.0314` and the code assumes the cycle closes after N frames.
**Why it's wrong:** it drifts; the loop no longer matches the original or a pinned picture.
**Fix:** derive the value from the frame counter (`angle = frame * step`, integer) or step an
integer phase.

### Divides, recomputes, wide integers, calls and tests in hot loops
| finding | error | fix |
|---|---|---|
| `div_loop` | divide by a non-constant every iteration | hoist a reciprocal, or a reciprocal table |
| `recompute` | the same costly op or libm call on the same inputs as last time | keep the last result |
| `i64_fits_i32` | i64 arithmetic whose results fit in i32 | use i32/u32 |
| `call_in_loop` | a small function called per pixel | inline it, or one call per span |
| `invariant_branch` | an `if` inside the loop that never flips in a frame | test once, two loops |
| `cache_hostile` | loads a cache line or more apart (column walks) | walk in memory order, transpose, tile |

## 5. The blitter (CHISEL)

### Tiny blits
**Error:** CHISEL for 8x8 tiles, a 2-row clear, or a scroll shift.
**Why it costs:** ~800 cycles fixed a blit; a CPU memset costs ~2.3 cycles a word.
**Detect:** `tiny_blits`.
**Fix:** the CPU below ~4 KiB; batch small blits into one big one; shift a scroller with a CPU
word shift.

### Copying inside one plane
**Error:** a CHISEL copy whose source and destination are in the same plane.
**Why it costs:** the overlap check (zm_blit_chk.v) runs it ordered, waiting on every write (~28
cycles a unit against ~2: `BLIT_UNIT_ORDERED`). Its destination span runs from the plane's BASE to the
box's last byte, so any source above or inside the box overlaps; one wholly below the box does not. A
source passed as a linear address (`CON2.SRC_ABS`, e.g. `blitter.blitRow` given a slice of the
plane) is still in the plane.
**Fix:** keep the source in cart RAM and copy from there.
**Seen:** deltaforce 60 → 40 fps until it did; dbug's zoomed scroller built each line in the plane and
`blitRow`ed it down (~77 K units a frame: 2.33 Mc of cart on the board, 33 fps).
**Found by:** `perf_audit` / `frame_cost` (`inplane_copy`, naming the site).

### Planar engines on a chunky machine
**Error:** a port that keeps the ST's interleaved bitplanes and converts them every frame.
**Fix:** draw chunky; convert the art once; blit with CHISEL from chunky art.
**Seen:** lockbuster2 ~22 → 60 fps, stcs 48 → 60.

## 6. Rasters and HBL handlers

### Fake rasters (bars drawn as pixels)
**Error:** colour bars blitted as a sprite or `@memset` per row into the framebuffer, often
copied from a CODEF remake.
**Fix:** a real raster: `zg.copper` or `zg.linepal`, running the full width, borders included
(see CLAUDE.md "Rasters", `apps/zig/scenes/replicants_emlyn/rasters.zig`).

### Per-line palettes copied by the CPU in an HBL
**Error:** an HBL handler that copies a palette each line.
**Why it costs:** the CPU runs between FRESCO's line passes; a handler plane can't join the
line-major group.
**Fix:** since HW 1.9.0, `zg.copper` / `zg.linepal` compile to a hardware copper list: the CPU
stores nothing a frame. Flag a handler that only writes registers as pure
(`setFrameBufferHBLHandlerPure`, HW 1.8.0) so its plane joins the line-major pass.
**Seen:** mpp_truecolor 4 PLANES 30 → 60 fps, tcb_colorshock ~0.83 Mc a frame of handler time gone.

## 7. Memory and data segment

### `self.* = .{}` on a big struct
**Error:** resetting a large struct with a default literal.
**Why it costs:** Zig emits a second copy of the whole default as a data segment (517 KB once,
which capped the sampler).
**Fix:** `@memset` the fields, or initialise them one by one.

### Zero-filled statics
**Error:** assuming a big zeroed `var` is free.
**Why it costs:** it can land in the data segment, on the disk and in the RAM window.
**Fix:** allocate it at init (`zg.mem`) or check `zero_segments` in the gate.

### Overrunning `vramAlloc`
**Error:** allocating more VRAM than the pool holds.
**Why it's wrong:** there is no guard: it silently overwrites the physical framebuffer.
**Fix:** budget the pool by hand and check the total.

### Huge unrolled loops
**Why it costs:** ZIGGY's I$ is 16 KB; a hot path that overflows it refetches at ~4× the cost.
**Fix:** unroll modestly; keep hot paths small.
