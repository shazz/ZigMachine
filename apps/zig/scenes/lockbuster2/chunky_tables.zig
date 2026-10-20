// --------------------------------------------------------------------------
// The planar engine's data, turned at COMPILE TIME into the shapes the chunky
// engine (chunky.zig) hands CHISEL: every table here is derived from
// engine.zig's own constants (the copy maps, the font, the header banks, the
// trail loops), so the two engines cannot drift apart on data.
//
// WHY THE SHAPES ARE BLITS. Every copy-map entry of all six engines has
// src mod 8 and dst mod 8 in {0, 1} (asserted below): with the plane word's
// interleave, the entry's four per-plane byte moves are exactly the four
// planes of ONE 8-pixel span, i.e. an 8x1 chunky copy; over the band's 25 rows
// (src and dst rows both step 160 bytes) it is ONE 8x25 column. Adjacent
// columns with the same shift merge into one wider blit (engines 1/3/5 are
// mostly the band shifted 8 px left). The trail passes move whole 160-byte rows
// by whole rows; the wedge clear of engine 4 zeroes whole plane words.
// --------------------------------------------------------------------------
const std = @import("std");
const ref = @import("engine.zig");
pub const trails = @import("chunky_trails.zig");

pub const W: usize = 320;
pub const H: usize = 200;

/// Planar bytes (groups of 8 = one 16-px chunk, plane words interleaved
/// p0 p1 p2 p3, high byte first) to palette indices; Go Pixels()' order.
pub fn expand(planar: []const u8, out: []u8) void {
    for (0..planar.len / 8) |c| {
        for (0..2) |half| {
            const b = planar[c * 8 + half ..];
            for (0..8) |bit| {
                const s: u3 = @intCast(7 - bit);
                const v = ((b[0] >> s) & 1) | ((b[2] >> s) & 1) << 1 | ((b[4] >> s) & 1) << 2 | ((b[6] >> s) & 1) << 3;
                out[c * 16 + half * 8 + bit] = v;
            }
        }
    }
}

// --- the font: one strip, glyph g at x = g*32, 25 rows -----------------------
pub const FONT_W: usize = ref.GLYPH_COUNT * 32;
pub const font: [FONT_W * 25]u8 = blk: {
    @setEvalBranchQuota(20_000_000);
    var out: [FONT_W * 25]u8 = undefined;
    for (0..ref.GLYPH_COUNT) |g| for (0..25) |y| {
        const src = ref.font_bin[g * ref.GLYPH_BYTES + y * 16 ..][0..16];
        expand(src, out[y * FONT_W + g * 32 ..][0..32]);
    };
    break :blk out;
};

// --- the two title banks: engine.zig's renderHeader bytes, row by row --------
/// Rows a slide copies: bank 0 101, bank 1 106 (16960 of the bank's 17000).
pub const HEADER_ROWS = [2]usize{ 101, 106 };
pub const headers: [2][106 * W]u8 = blk: {
    @setEvalBranchQuota(40_000_000);
    var out: [2][106 * W]u8 = undefined;
    for (0..2) |bank| {
        var h: [ref.HEADER_BYTES]u8 = undefined;
        ref.Engine.renderHeader(bank, &h);
        expand(h[0 .. 106 * 160], &out[bank]);
    }
    break :blk out;
};

// --- the copy maps as blits ---------------------------------------------------
/// One map blit, rows relative to the band's top row and its base: dst
/// (dr, dx) <- src (sr, sx), `w` px wide, the band's height tall.
pub const Span = struct { dr: i16, dx: u16, sr: i16, sx: u16, w: u16 };
pub const MapPass = struct { spans: []const Span, text_dr: i16, text_dx: u16 };

/// A signed screen-byte offset to (row, x); only the 8-px aligned bytes exist.
fn rowX(b: i32) [2]i32 {
    const r = @divFloor(b, 160);
    const c = b - r * 160;
    if (@mod(c, 8) > 1) @compileError("lockbuster2: a copy-map byte is not an 8-px span");
    return .{ r, @divFloor(c, 8) * 16 + @mod(c, 2) * 8 };
}

fn mapPass(comptime mode: usize) MapPass {
    var raw: [40]Span = undefined;
    var n: usize = 0;
    var text: ?[2]i32 = null;
    for (ref.maps[mode]) |op| {
        const d = rowX(op.dst);
        if (op.src == 0x7fff) {
            if (text != null) @compileError("lockbuster2: two text spans");
            text = d;
            continue;
        }
        const s = rowX(op.src);
        raw[n] = .{ .dr = @intCast(d[0]), .dx = @intCast(d[1]), .sr = @intCast(s[0]), .sx = @intCast(s[1]), .w = 8 };
        n += 1;
    }
    // Distinct destinations (no entry overwrites another), so the order is free:
    // sort by (dr, dx) and merge neighbours that shift by the same amount.
    for (0..n) |i| for (i + 1..n) |j| {
        if (raw[i].dr == raw[j].dr and raw[i].dx == raw[j].dx) @compileError("lockbuster2: overlapping map entries");
        if (raw[j].dr < raw[i].dr or (raw[j].dr == raw[i].dr and raw[j].dx < raw[i].dx)) {
            const t = raw[i];
            raw[i] = raw[j];
            raw[j] = t;
        }
    };
    var out: [40]Span = undefined;
    var m: usize = 0;
    for (raw[0..n]) |s| {
        if (m > 0) {
            const p = &out[m - 1];
            if (p.dr == s.dr and p.sr == s.sr and p.dx + p.w == s.dx and p.sx + p.w == s.sx) {
                p.w += 8;
                continue;
            }
        }
        out[m] = s;
        m += 1;
    }
    const t = text orelse @compileError("lockbuster2: a map without its text span");
    const final = out[0..m].*;
    return .{ .spans = &final, .text_dr = @intCast(t[0]), .text_dx = @intCast(t[1]) };
}

pub const maps: [6]MapPass = blk: {
    @setEvalBranchQuota(1_000_000);
    var out: [6]MapPass = undefined;
    for (0..6) |m| out[m] = mapPass(m);
    break :blk out;
};

/// Go Step()'s band top row per engine (base / 160 - ORIGIN / 160).
pub fn baseRow(mode: usize) i32 {
    return 87 + @as(i32, switch (mode) {
        3 => 15,
        4 => -20,
        5 => -15,
        else => 0,
    });
}

pub fn bandHeight(mode: usize) i32 {
    return if (mode == 5) 24 else 25;
}

comptime {
    // Every row a map pass READS is on screen, so a 200-row surface holds all
    // the ring the picture can ever see (the off-screen ring is write-only).
    for (0..6) |m| {
        for (maps[m].spans) |s| {
            const top = baseRow(m) + s.sr;
            if (top < 0 or top + bandHeight(m) > H or s.sx + s.w > W or s.dx + s.w > W)
                @compileError("lockbuster2: a map span reads off screen");
        }
        // ...and so is every row a trail pass reads.
        const p = trails.passes[m];
        if (baseRow(m) + p.src_lo < 0 or baseRow(m) + p.src_hi >= H)
            @compileError("lockbuster2: a trail reads off screen");
    }
}
