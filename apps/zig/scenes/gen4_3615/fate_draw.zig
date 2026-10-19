// --------------------------------------------------------------------------
// Painting the FATE logo's slices into the scroller's box (fate.zig places
// them; this draws them).
//
// The JS draws the slices back to front, each over the last. Here they are
// painted FRONT to back and each box row remembers the span already painted,
// so a pixel is stored once however many slices cover it. That is exact
// because every slice's span contains canvas x ~312..451 (its centre
// 120000/(z+200) - 357 + l/2 stays within 375..388 and l >= 152), so the spans
// on a row always overlap and what is painted stays one interval. Should a
// span ever miss it, the frame is painted back to front instead, as the JS does.
// --------------------------------------------------------------------------
const std = @import("std");
const A = @import("assets.zig");
const Slice = @import("fate.zig").Slice;

const ROWS = 112; // the_fate.png is 320x112: slice 111 is one row, 112 none
const SRC_W = 320;
const MAX_H = 128; // box rows tracked (the scroller's box is 88)

/// The box rows a frame painted, [lo, hi).
pub const Rows = struct { lo: usize, hi: usize };

/// One slice row in box coordinates: columns [lo, hi), the source row, and
/// the 16.16 walk (Chrome's nearest-neighbour scaler: half a step in, the step
/// truncated; measured against Chrome, see gen4_3615_replay.mjs).
const Span = struct { by: usize, lo: i32, hi: i32, src: []const u8, s: Slice, step: u32 };

fn span(s: Slice, dy: u1, bg_w: usize, bg_h: usize, ox: i32, oy: i32) ?Span {
    const cy = s.y + dy;
    const row = @as(usize, s.i) + dy;
    if (@mod(cy, 2) != 0 or row >= ROWS) return null;
    const by = @divExact(cy, 2) - oy;
    if (by < 0 or by >= bg_h) return null;
    if (s.l <= 0) return null; // 264 + 5.6z >= 152 on every curve; drawImage would draw nothing
    const lo = @max(@divFloor(s.x + 1, 2), ox) - ox; // first even canvas x >= s.x
    const hi = @min(@divFloor(s.x + s.l + 1, 2), ox + @as(i32, @intCast(bg_w))) - ox;
    if (lo >= hi) return null;
    // u32 throughout (rv32 does i64 in pairs): step <= (320 << 16) / 152, the
    // walk stays under (l + 2) * step, about 21 M
    const step: u32 = (@as(u32, SRC_W) << 16) / @as(u32, @intCast(s.l));
    return .{ .by = @intCast(by), .lo = lo, .hi = hi, .src = A.fate.data[(row >> 1) * A.fate.w ..][0..A.fate.w], .s = s, .step = step };
}

/// Paint box columns [a, b) of span p into row `out` (4-aligned), a word at a time.
fn paint(out: []u8, p: Span, ox: i32, a: i32, b: i32) void {
    if (a >= b) return;
    const d: u32 = @intCast(2 * (a + ox) - p.s.x); // >= 0: a is at or right of the slice's x
    var acc: u32 = p.step / 2 + d * p.step;
    const inc = 2 * p.step;
    var i: usize = @intCast(a);
    const end: usize = @intCast(b);
    while (i < end and i & 3 != 0) : (i += 1) {
        out[i] = p.src[acc >> 17]; // (acc >> 16) >> 1: the halved art
        acc += inc;
    }
    while (i + 4 <= end) : (i += 4) {
        var w: u32 = 0;
        inline for (0..4) |k| {
            w |= @as(u32, p.src[acc >> 17]) << (8 * k);
            acc += inc;
        }
        @as(*u32, @ptrCast(@alignCast(out[i..].ptr))).* = w;
    }
    while (i < end) : (i += 1) {
        out[i] = p.src[acc >> 17];
        acc += inc;
    }
}

/// Draw `slices` (back to front) into `bg`, a `bg_w`-wide buffer whose (0, 0)
/// is ST pixel (ox, oy); rows start 4-aligned.
pub fn draw(slices: []const Slice, bg: []u8, bg_w: usize, ox: i32, oy: i32) Rows {
    const bg_h = bg.len / bg_w;
    std.debug.assert(bg_h <= MAX_H and bg_w % 4 == 0);
    var lo_c: [MAX_H]i16 = undefined; // per row, the painted span [lo_c, hi_c)
    var hi_c: [MAX_H]i16 = undefined;
    @memset(lo_c[0..bg_h], 0);
    @memset(hi_c[0..bg_h], 0);
    var rows = Rows{ .lo = bg_h, .hi = 0 };
    var i = slices.len;
    while (i > 0) {
        i -= 1;
        for (0..2) |dy| {
            const p = span(slices[i], @intCast(dy), bg_w, bg_h, ox, oy) orelse continue;
            const out = bg[p.by * bg_w ..][0..bg_w];
            const clo: i32 = lo_c[p.by];
            const chi: i32 = hi_c[p.by];
            if (clo == chi) {
                paint(out, p, ox, p.lo, p.hi);
            } else if (p.hi < clo or p.lo > chi) {
                return backToFront(slices, bg, bg_w, ox, oy);
            } else {
                paint(out, p, ox, p.lo, clo);
                paint(out, p, ox, chi, p.hi);
            }
            lo_c[p.by] = @intCast(if (clo == chi) p.lo else @min(clo, p.lo));
            hi_c[p.by] = @intCast(if (clo == chi) p.hi else @max(chi, p.hi));
            rows = .{ .lo = @min(rows.lo, p.by), .hi = @max(rows.hi, p.by + 1) };
        }
    }
    return if (rows.lo < rows.hi) rows else .{ .lo = 0, .hi = 0 };
}

fn backToFront(slices: []const Slice, bg: []u8, bg_w: usize, ox: i32, oy: i32) Rows {
    const bg_h = bg.len / bg_w;
    var rows = Rows{ .lo = bg_h, .hi = 0 };
    for (slices) |s| for (0..2) |dy| {
        const p = span(s, @intCast(dy), bg_w, bg_h, ox, oy) orelse continue;
        paint(bg[p.by * bg_w ..][0..bg_w], p, ox, p.lo, p.hi);
        rows = .{ .lo = @min(rows.lo, p.by), .hi = @max(rows.hi, p.by + 1) };
    };
    return if (rows.lo < rows.hi) rows else .{ .lo = 0, .hi = 0 };
}
