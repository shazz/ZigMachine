// --------------------------------------------------------------------------
// The ten distortions the lab compares, all filters over ONE text source: the
// band is rendered into `strip` once a frame and every mode reads it, as screen
// 345 renders its scroller to a canvas and distorts the canvas (345:400-404,
// 442). One text, ten filters.
//
// Modes 2-8 are CODEF's own filters, from prototypes/codef/484/lib/codef_fx.js:
//   siny  (33-53)  per-COLUMN vertical OFFSET -> 2-6   sinx (80-96) per-ROW
//   horizontal -> 7   zoomy (55-78) per-COLUMN vertical SCALE -> 8
// Each sums a LIST of sines and keeps CODEF's separation of the two phases:
// `inc` advances `value` per pixel (the wavelength) and `offset` per frame (the
// travel), the per-pixel walk snapshotted and restored so the two never
// contaminate each other. Transliterated, not reinvented; each mode keeps its
// OWN params, as 484 keeps an FX per layer. Mode 9 is a 2D path (path.zig) and
// mode 10 is 345's own table (table345.zig) — neither is a height field.
//
// WHAT `offset` DOES, since it is the whole rollercoaster question. A column is
// drawn at y = sum(amp*sin(value)), value = v0 + inc*x, and v0 += offset a
// frame, so a point of constant phase moves at dx/dt = -offset/inc. offset = 0
// PINS the curve in screen space and the letters ride through it, each climbing
// and dropping because IT moves. A non-zero offset slides the curve instead.
//
// Canvas to ST: 484 authored doubled, so amp HALVES and inc DOUBLES; offset is
// per frame and unchanged.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const blit = zg.blit;
const path = @import("path.zig"); // mode 9: a 2D track, loop included
const table345 = @import("table345.zig"); // mode 10: screen 345's own playlist
const sines = @import("sines.zig"); // the term walk, in integers
const Param = sines.Param;
const MAX_TERMS = sines.MAX_TERMS;

pub const Mode = enum(u8) { flat, sine_letter, sine_column, codef484, codef484_static, coaster, rubber, pipe, path, table345 };
pub const NAMES = [_][]const u8{
    "1 FLAT",
    "2 SINE PER LETTER",
    "3 SINE PER COLUMN",
    "4 CODEF 484 MIDDLE",
    "5 CODEF 484 STATIC",
    "6 ROLLERCOASTER",
    "7 RUBBER PER ROW",
    "8 PIPE COLUMN ZOOM",
    "9 PATH WITH A LOOP",
    "0 345 TABLE SHAKE",
};

pub const TILE = 32; // the font's cell, and one letter of the ring
/// Longer than the screen: mode 9's track is a squiggle whose arc length is
/// twice the width, and the text fills all of it. Modes 1-8 clip past 320.
pub const W = 704;
// V8 Populous (apps/rust/scenes/v8_populous/scroll.rs:124): one sine, amp 40
// canvas = 20 ST, stepped per LETTER — the baseline Matt called too nice. `inc`
// is PER COLUMN, identical to p_column's, and siny multiplies it by the stride,
// so a letter advances exactly 0.55 and modes 2 and 3 are the SAME curve
// sampled two ways. (Read as a per-LETTER rate it advanced 2.8 turns a letter
// and aliased the baseline into noise.)
var p_letter = [_]Param{.{ .value = 0, .amp = 20, .inc = 0.55 / @as(f64, TILE), .offset = -0.05 }};
// The same curve per COLUMN: same inc, so only the sampling differs.
var p_column = [_]Param{.{ .value = 0, .amp = 20, .inc = 0.55 / @as(f64, TILE), .offset = -0.05 }};

// CODEF 484 VERBATIM (cascade-archeology.js:76-79), halved/doubled for ST; 484
// feeds these to sinx, its siny scroller (72-73) differing only in amp 50.
var p_484 = [_]Param{
    .{ .value = 0, .amp = 10, .inc = 0.06, .offset = -0.05 }, // the short ripple
    .{ .value = 0, .amp = 20, .inc = 0.02, .offset = -0.04 }, // the long swell
};
// The SAME curve with the travel out: the hills stand still and the letters
// ride them. One number from the mode above, deliberately.
var p_484_static = [_]Param{
    .{ .value = 0, .amp = 10, .inc = 0.06, .offset = 0 },
    .{ .value = 0, .amp = 20, .inc = 0.02, .offset = 0 },
};
// OURS. Harmonics (inc, 2*inc, 3*inc) with their own phases so the climb is not
// the drop's mirror, plus a negative-amp trough (CODEF `type` 1) for a cusped
// valley. Offsets 0: the track is fixed and the letters ride it.
var p_coaster = [_]Param{
    .{ .value = 0, .amp = 22, .inc = 0.022, .offset = 0 },
    .{ .value = 1.1, .amp = 11, .inc = 0.044, .offset = 0 },
    .{ .value = 2.7, .amp = 5, .inc = 0.066, .offset = 0 },
    .{ .value = 0.4, .amp = -9, .inc = 0.011, .offset = 0 },
};
// The rubber uses 484's own numbers on the axis 484 uses them on.
var p_rubber = [_]Param{
    .{ .value = 0, .amp = 10, .inc = 0.06, .offset = -0.05 },
    .{ .value = 0, .amp = 20, .inc = 0.02, .offset = -0.04 },
};
// codef_fx.zoomy passes the raw sum as the zoom, which crosses zero and flips;
// 484 never calls it, so PIPE_BASE is ours.
const PIPE_BASE = 1.0;
var p_pipe = [_]Param{.{ .value = 0, .amp = 0.75, .inc = 0.04, .offset = -0.06 }};
/// The one text source: the band, flat, before anything distorts it.
/// 22,528 B on zg.mem, taken once by init() (once per cart load).
var strip: *[TILE][W]u8 = undefined;

pub const Glyph = struct { x: i32, cell: blit.Rect };
pub fn init() void {
    strip = zg.mem.mustAlloc([W]u8, TILE)[0..TILE];
    path.buildPath();
    table345.buildTable();
    for ([_][]Param{ &p_letter, &p_column, &p_484, &p_484_static, &p_coaster, &p_rubber, &p_pipe }) |ps| sines.prepare(ps, TILE);
}

pub fn fillStrip(font: blit.Image, glyphs: []const Glyph) void {
    for (strip) |*r| @memset(r, 0);
    const dst = blit.Dst.buffer(std.mem.asBytes(strip), W);
    for (glyphs) |g| blit.blit(dst, font, g.cell, g.x, 0, 0, .copy);
}

fn paramsOf(mode: Mode) []Param {
    return switch (mode) {
        .flat, .path, .table345 => p_column[0..0],
        .sine_letter => &p_letter,
        .sine_column => &p_column,
        .codef484 => &p_484,
        .codef484_static => &p_484_static,
        .coaster => &p_coaster,
        .rubber => &p_rubber,
        .pipe => &p_pipe,
    };
}

/// `align_x` is where the letters' 32-pixel blocks start, so SINE PER LETTER
/// steps on the letter boundaries. `travel` is the lab's live knob: pixels a
/// frame the curve slides, on top of the mode's offsets, as a rigid
/// translation (offset = -travel*inc). Mode 9 reads it as arc pixels a frame.
/// `steps` is the travel in quarter pixels (the lab's TRAVEL_STEP units).
pub fn draw(mode: Mode, dst: blit.Dst, row: i32, align_x: usize, steps: i32, frame: u32) void {
    const travel: f64 = 0.25 * @as(f64, @floatFromInt(steps));
    const src = blit.Image.init(std.mem.asBytes(strip), W);
    const p = paramsOf(mode);
    switch (mode) {
        .flat => blit.blit(dst, src, null, 0, row, 0, .copy),
        .path => path.draw(dst, strip, @as(i64, steps) * frame),
        .table345 => table345.draw(dst, src, row, frame),
        .rubber => sinx(dst, src, p, row, travel),
        .pipe => zoomy(dst, src, p, row, travel),
        .sine_letter => siny(dst, src, p, row, travel, TILE, align_x),
        else => siny(dst, src, p, row, travel, 1, 0),
    }
}

/// codef_fx.siny: column i goes to (i, sum + posy); `stride` columns share one
/// phase step — 1 per column, TILE per letter.
fn siny(dst: blit.Dst, src: blit.Image, params: []Param, posy: i32, travel: f64, stride: usize, align_x: usize) void {
    var w = sines.begin(params);
    for (0..src.w) |i| {
        const cell = blit.Rect{ .x = i, .y = 0, .w = 1, .h = src.h };
        blit.blit(dst, src, cell, @intCast(i), posy + sines.roundQ38(sines.sumQ38(params, &w)), 0, .copy);
        // the LAST column of each aligned block: every column of a letter
        // shares one phase, and the step lands on the boundary between letters
        if (i % stride == (align_x + stride - 1) % stride) sines.step(params, &w, stride != 1);
    }
    sines.advance(params, travel);
}

/// codef_fx.sinx: source ROW i goes to (sum + posx, i).
fn sinx(dst: blit.Dst, src: blit.Image, params: []Param, posy: i32, travel: f64) void {
    var w = sines.begin(params);
    for (0..src.h) |i| {
        const cell = blit.Rect{ .x = 0, .y = i, .w = src.w, .h = 1 };
        blit.blit(dst, src, cell, sines.roundQ38(sines.sumQ38(params, &w)), posy + @as(i32, @intCast(i)), 0, .copy);
        sines.step(params, &w, false);
    }
    sines.advance(params, travel);
}

/// codef_fx.zoomy: the sum is a vertical SCALE, the column growing downward
/// from posy. Written out: nothing here scales a single column. The source row
/// of output row r is round(r / zoom), walked as r * (1 / zoom) in Q24: one f32
/// divide a column, none a pixel.
fn zoomy(dst: blit.Dst, src: blit.Image, params: []Param, posy: i32, travel: f64) void {
    var w = sines.begin(params);
    const band = strip; // one load of the arena pointer, not one a pixel
    const h: i32 = @intCast(src.h);
    for (0..src.w) |i| {
        const zoom_q16: i32 = 65536 + @as(i32, @intCast((sines.sumQ38(params, &w) + (1 << 21)) >> 22));
        sines.step(params, &w, false);
        if (zoom_q16 <= 0 or i >= dst.w) continue;
        const rows = (h * zoom_q16 + 32768) >> 16; // round(src.h * zoom)
        const inv = 65536.0 / @as(f32, @floatFromInt(zoom_q16)); // 1 / zoom
        const inv_q24: i32 = @intFromFloat(inv * 16777216.0);
        var acc: i32 = 0;
        var r: i32 = 0;
        while (r < rows) : ({
            r += 1;
            acc += inv_q24;
        }) {
            const sr = (acc + (1 << 23)) >> 24;
            const y = posy + r;
            if (sr < 0 or sr >= h or y < 0 or y >= dst.h) continue;
            const p = band[@intCast(sr)][i];
            if (p != 0) dst.buf[@as(usize, @intCast(y)) * dst.stride + i] = p;
        }
    }
    sines.advance(params, travel);
}
