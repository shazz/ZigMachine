// --------------------------------------------------------------------------
// STOS `unpack`: the COMPACT extension's depacker (COMPACT.EXA $488-$614),
// transcribed. Header ($06071963): +4 resolution, +6 x (16-px units), +8 y,
// +$A width (16-px units), +$C height (blocks), +$10 block height (lines),
// +$12 flags (bit 1: Setpalette after), +$14 / +$18 the offsets of the flag
// bytes and of their refresh bitmap, +$26 the palette, +$46 the value bytes.
//
// Each plane byte-column is walked down one block: a set flag bit takes a new
// value byte, a clear one repeats the last. A flag byte serves 8 lines, then a
// refresh-bitmap bit says whether the next 8 take a new flag byte. The planes
// are walked in turn and the stream state carries over from one to the next.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const scr = @import("scr.zig");

const LINE: usize = 160;
var planar: []u8 = &.{};

const Stream = struct {
    p: []const u8,
    a4: usize,
    a5: usize,
    a6: usize,
    d0: u3 = 7,
    d1: i8 = 7,
    d2: u8 = 0,
    d3: u8 = 0,

    fn next(s: *Stream) u8 {
        if (s.d2 >> s.d0 & 1 != 0) {
            s.d3 = s.p[s.a4];
            s.a4 += 1;
        }
        const v = s.d3;
        if (s.d0 == 0) {
            s.d0 = 7;
            s.refresh();
        } else s.d0 -= 1;
        return v;
    }

    fn refresh(s: *Stream) void {
        if (s.p[s.a6] >> @intCast(s.d1) & 1 != 0) {
            s.d2 = s.p[s.a5];
            s.a5 += 1;
        }
        s.d1 -= 1;
        if (s.d1 < 0) {
            s.d1 = 7;
            s.a6 += 1;
        }
    }
};

fn be16(p: []const u8, o: usize) usize {
    return std.mem.readInt(u16, p[o..][0..2], .big);
}

fn be32(p: []const u8, o: usize) usize {
    return std.mem.readInt(u32, p[o..][0..4], .big);
}

/// Unpack `p` into screen `dst` and its palette; true if flags bit 1 asks
/// for the palette to be set (every SKYSTRIKE picture does).
pub fn unpack(p: []const u8, dst: scr.Id) bool {
    if (planar.len == 0) planar = zg.mem.mustAlloc(u8, 32000);
    @memset(planar, 0);
    var s = Stream{ .p = p, .a4 = 0x46, .a5 = be32(p, 0x14), .a6 = be32(p, 0x18) };
    s.d2 = p[s.a5];
    s.a5 += 1;
    s.d3 = p[s.a4];
    s.a4 += 1;
    s.refresh();
    const base = be16(p, 6) * 8 + be16(p, 8) * LINE;
    for (0..4) |plane| walkPlane(&s, base + plane * 2, be16(p, 0xA), be16(p, 0xC), be16(p, 0x10));
    toChunky(planar, scr.get(dst));
    for (&scr.pal[@intFromEnum(dst)], 0..) |*c, i| c.* = @intCast(be16(p, 0x26 + i * 2));
    return be16(p, 0x12) & 2 != 0;
}

fn walkPlane(s: *Stream, a3: usize, w: usize, h: usize, bh: usize) void {
    for (0..h) |row| {
        const a2 = a3 + row * bh * LINE;
        for (0..w) |col| {
            for (0..2) |half| {
                var a0 = a2 + col * 8 + half;
                for (0..bh) |_| {
                    const v = s.next();
                    if (a0 < planar.len) planar[a0] = v;
                    a0 += LINE;
                }
            }
        }
    }
}

/// 32000 bytes of low-res planes -> 64000 palette indices.
pub fn toChunky(src: []const u8, dst: []u8) void {
    for (0..200) |y| {
        for (0..20) |g| {
            const o = y * LINE + g * 8;
            for (0..16) |b| {
                const bit: u4 = @intCast(15 - b);
                var v: u8 = 0;
                for (0..4) |pl| {
                    const w: u16 = @as(u16, src[o + pl * 2]) << 8 | src[o + pl * 2 + 1];
                    v |= @as(u8, @intCast(w >> bit & 1)) << @intCast(pl);
                }
                dst[y * 320 + g * 16 + b] = v;
            }
        }
    }
}
