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
const MAX_TERMS = 4;
/// codef_fx's `params` entry, with its names.
const Param = struct { value: f64, amp: f64, inc: f64, offset: f64 };
// V8 Populous (apps/rust/scenes/v8_populous/scroll.rs:124): one sine, amp 40
// canvas = 20 ST, stepped per LETTER — the baseline Matt called too nice. `inc`
// is PER COLUMN, identical to p_column's, and siny multiplies it by the stride,
// so a letter advances exactly 0.55 and modes 2 and 3 are the SAME curve
// sampled two ways. (Read as a per-LETTER rate it advanced 2.8 turns a letter
// and aliased the baseline into noise.)
var p_letter = [_]Param{.{ .value = 0, .amp = 20, .inc = 0.55 / @as(f64, TILE), .offset = -0.05 }};
// The same curve per COLUMN: same inc, so only the sampling differs.
var p_column = [_]Param{.{ .value = 0, .amp = 20, .inc = 0.55 / @as(f64, TILE), .offset = -0.05 }};// CODEF 484 VERBATIM (cascade-archeology.js:76-79), halved/doubled for ST; 484
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
var strip: [TILE][W]u8 = undefined;

pub const Glyph = struct { x: i32, cell: blit.Rect };
pub fn init() void {
    path.buildPath();
    table345.buildTable();
}

pub fn fillStrip(font: blit.Image, glyphs: []const Glyph) void {
    for (&strip) |*r| @memset(r, 0);
    const dst = blit.Dst.buffer(std.mem.asBytes(&strip), W);
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
pub fn draw(mode: Mode, dst: blit.Dst, row: i32, align_x: usize, travel: f64, frame: u32) void {
    const src = blit.Image.init(std.mem.asBytes(&strip), W);
    const p = paramsOf(mode);
    switch (mode) {
        .flat => blit.blit(dst, src, null, 0, row, 0, .copy),
        .path => path.draw(dst, &strip, travel * @as(f64, @floatFromInt(frame))),
        .table345 => table345.draw(dst, src, row, frame),
        .rubber => sinx(dst, src, p, row, travel),
        .pipe => zoomy(dst, src, p, row, travel),
        .sine_letter => siny(dst, src, p, row, travel, TILE, align_x),
        else => siny(dst, src, p, row, travel, 1, 0),
    }
}

fn sum(params: []const Param) f64 {
    var v: f64 = 0;
    for (params) |p| v += @sin(p.value) * p.amp;
    return v;
}
fn round(v: f64) i32 {
    return @intFromFloat(@round(v));
}

/// codef_fx's bookkeeping: snapshot, walk, restore plus the per-frame step.
fn advance(params: []Param, old: *const [MAX_TERMS]f64, travel: f64) void {
    for (params, 0..) |*p, j| p.value = old[j] + p.offset - travel * p.inc;
}
fn snapshot(params: []const Param, old: *[MAX_TERMS]f64) void {
    for (params, 0..) |p, j| old[j] = p.value;
}

/// codef_fx.siny: column i goes to (i, sum + posy); `stride` columns share one
/// phase step — 1 per column, TILE per letter.
fn siny(dst: blit.Dst, src: blit.Image, params: []Param, posy: i32, travel: f64, stride: usize, align_x: usize) void {
    var old: [MAX_TERMS]f64 = undefined;
    snapshot(params, &old);
    for (0..src.w) |i| {
        const cell = blit.Rect{ .x = i, .y = 0, .w = 1, .h = src.h };
        blit.blit(dst, src, cell, @intCast(i), posy + round(sum(params)), 0, .copy);
        // the LAST column of each aligned block: every column of a letter
        // shares one phase, and the step lands on the boundary between letters
        if (i % stride == (align_x + stride - 1) % stride) for (params) |*p| {
            p.value += p.inc * @as(f64, @floatFromInt(stride));
        };
    }
    advance(params, &old, travel);
}

/// codef_fx.sinx: source ROW i goes to (sum + posx, i).
fn sinx(dst: blit.Dst, src: blit.Image, params: []Param, posy: i32, travel: f64) void {
    var old: [MAX_TERMS]f64 = undefined;
    snapshot(params, &old);
    for (0..src.h) |i| {
        const cell = blit.Rect{ .x = 0, .y = i, .w = src.w, .h = 1 };
        blit.blit(dst, src, cell, round(sum(params)), posy + @as(i32, @intCast(i)), 0, .copy);
        for (params) |*p| p.value += p.inc;
    }
    advance(params, &old, travel);
}

/// codef_fx.zoomy: the sum is a vertical SCALE, the column growing downward
/// from posy. Written out: nothing here scales a single column.
fn zoomy(dst: blit.Dst, src: blit.Image, params: []Param, posy: i32, travel: f64) void {
    var old: [MAX_TERMS]f64 = undefined;
    snapshot(params, &old);
    for (0..src.w) |i| {
        const zoom = PIPE_BASE + sum(params);
        for (params) |*p| p.value += p.inc;
        if (zoom <= 0 or i >= dst.w) continue;
        var r: i32 = 0;
        while (r < round(@as(f64, @floatFromInt(src.h)) * zoom)) : (r += 1) {
            const sr = round(@as(f64, @floatFromInt(r)) / zoom);
            const y = posy + r;
            if (sr < 0 or sr >= src.h or y < 0 or y >= dst.h) continue;
            const p = strip[@intCast(sr)][i];
            if (p != 0) dst.buf[@as(usize, @intCast(y)) * dst.stride + i] = p;
        }
    }
    advance(params, &old, travel);
}
