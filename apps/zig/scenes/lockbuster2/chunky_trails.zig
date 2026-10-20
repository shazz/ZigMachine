// --------------------------------------------------------------------------
// engine.zig's pass() -- the glyph trails and engine 4's wedge -- in whole
// chunky rows, derived at COMPILE TIME by running pass()'s own loops on row
// numbers instead of bytes (every offset in them is a multiple of 160, which
// is asserted). The planar memmoves run in a fixed order; this file proves that
// the order cannot matter (no trail writes a row any trail reads, no two write
// the same row), so rows may be merged into rectangles and the 2-row doubles
// become one blit whose source stride is 0.
// --------------------------------------------------------------------------
const std = @import("std");

/// dst rows dst .. dst+h-1 (and dst+h when `double`, which is only ever h = 1)
/// <- src rows src .. src+h-1; rows relative to the band's base row.
pub const Trail = struct { src: i16, dst: i16, h: u8, double: bool };
/// The trail rows of one engine and the span of rows they read.
pub const Pass = struct { rows: []const Trail, src_lo: i16, src_hi: i16 };

fn row(comptime off: i32) i16 {
    if (@mod(off, 160) != 0) @compileError("lockbuster2: a trail offset is not whole rows");
    return @intCast(@divExact(off, 160));
}

const List = struct {
    t: [64]Trail = undefined,
    n: usize = 0,
    fn add(l: *List, src: i32, dst: i32, double: bool) void {
        l.t[l.n] = .{ .src = @intCast(src), .dst = @intCast(dst), .h = 1, .double = double };
        l.n += 1;
    }
    /// Go copyRows(): src steps one row down, dst `stride` rows.
    fn copyRows(l: *List, src: i32, dst: i32, rows: usize, stride: i32, double: bool) void {
        for (0..rows) |i| l.add(src + @as(i32, i), dst + stride * @as(i32, i), double);
    }
};

fn generate(comptime mode: usize) List {
    var l = List{};
    switch (mode) {
        0 => l.copyRows(0, row(0x38e0), 24, -2, false),
        1 => l.copyRows(1, row(0x3700), 23, -2, true),
        2 => l.copyRows(0, row(0x46a0), 35, -2, false),
        3 => {
            var src: i32 = 0;
            var dst: i32 = -row(0x2a80);
            var stride: i32 = 1;
            var count: i32 = 22;
            while (count >= 0) : (count -= 1) {
                l.add(src, dst, true); // the two memmoves: dst and dst+160
                src += 1;
                dst += 1;
                if (count == 20) stride += 1;
                dst += stride;
            }
        },
        4 => l.copyRows(0, row(0x3e80), 29, -2, false),
        5 => for (0..24) |yu| {
            const y: i32 = yu;
            l.add(y, y + row(0x2bc0), false);
            l.add(y, y + row(0x2bc0) - row(0x5140), false);
        },
        else => unreachable,
    }
    return l;
}

fn lastDst(t: Trail) i32 {
    return t.dst + t.h - 1 + @intFromBool(t.double);
}

fn pass(comptime mode: usize) Pass {
    var l = generate(mode);
    const ts = l.t[0..l.n];
    // Order-free: no destination row is read by any trail, none written twice.
    for (ts, 0..) |a, i| for (ts, 0..) |b, j| {
        if (a.dst <= b.src and b.src <= lastDst(a)) @compileError("lockbuster2: a trail reads a trail's row");
        if (i != j and a.dst <= lastDst(b) and b.dst <= lastDst(a)) @compileError("lockbuster2: trails overlap");
    };
    // So sort by destination and merge runs that move a block down together.
    for (0..ts.len) |i| for (i + 1..ts.len) |j| if (ts[j].dst < ts[i].dst) {
        const t = ts[i];
        ts[i] = ts[j];
        ts[j] = t;
    };
    var out: [64]Trail = undefined;
    var m: usize = 0;
    var lo: i16 = std.math.maxInt(i16);
    var hi: i16 = std.math.minInt(i16);
    for (ts) |t| {
        lo = @min(lo, t.src);
        hi = @max(hi, t.src + t.h - 1);
        if (m > 0) {
            const p = &out[m - 1];
            if (!p.double and !t.double and p.dst + p.h == t.dst and p.src + p.h == t.src) {
                p.h += 1;
                continue;
            }
        }
        out[m] = t;
        m += 1;
    }
    const final = out[0..m].*;
    return .{ .rows = &final, .src_lo = lo, .src_hi = hi };
}

pub const passes: [6]Pass = blk: {
    @setEvalBranchQuota(1_000_000);
    var out: [6]Pass = undefined;
    for (0..6) |m| out[m] = pass(m);
    break :blk out;
};

// --- engine 4's wedge clear ---------------------------------------------------
// Each clear() of the planar loop zeroes whole plane WORDS: in chunky, the
// fully cleared 16-px groups are a fill with 0 and the partly cleared ones keep
// only their surviving planes (index AND keep).
pub const Fill = struct { x: u16, y: u16, w: u16, h: u16 };
pub const Mask = struct { x: u16, y: u16, w: u16, keep: u8 };
pub const Wedge = struct { fills: []const Fill, masks: []const Mask };

pub const wedge: Wedge = blk: {
    @setEvalBranchQuota(2_000_000);
    // planes cleared per (row, 8-px group), rows relative to the screen top
    var cleared: [200][40]u4 = .{.{0} ** 40} ** 200;
    var pos: i32 = 0x50f0;
    var delta: i32 = 238;
    var count: i32 = 19;
    while (count >= 0) : (count -= 1) {
        const n: i32 = (count + 21) * 2;
        for (0..n) |k| {
            const b = pos + @as(i32, k);
            const r = @divFloor(b, 160);
            const c = b - r * 160; // byte in row: chunk c/8, plane (c%8)/2, half c%2
            cleared[r][@divFloor(c, 8) * 2 + @mod(c, 2)] |= @as(u4, 1) << @intCast(@divFloor(@mod(c, 8), 2));
        }
        pos += n - delta;
        delta -= 2;
    }
    var fills: [64]Fill = undefined;
    var nf: usize = 0;
    var masks: [64]Mask = undefined;
    var nm: usize = 0;
    for (0..200) |r| {
        var g: usize = 0;
        while (g < 40) {
            const keep: u8 = ~@as(u8, cleared[r][g]) & 0xF;
            var e = g + 1;
            while (e < 40 and cleared[r][e] == cleared[r][g]) e += 1;
            const x: u16 = g * 8;
            const w: u16 = (e - g) * 8;
            if (keep == 0) {
                // a zero run: extend the previous fill one row down when it lines up
                if (nf > 0 and fills[nf - 1].x == x and fills[nf - 1].w == w and fills[nf - 1].y + fills[nf - 1].h == r) {
                    fills[nf - 1].h += 1;
                } else {
                    fills[nf] = .{ .x = x, .y = r, .w = w, .h = 1 };
                    nf += 1;
                }
            } else if (keep != 0xF) {
                masks[nm] = .{ .x = x, .y = r, .w = w, .keep = keep };
                nm += 1;
            }
            g = e;
        }
    }
    const f = fills[0..nf].*;
    const m = masks[0..nm].*;
    break :blk .{ .fills = &f, .masks = &m };
};
