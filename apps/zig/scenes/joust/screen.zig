// --------------------------------------------------------------------------
// The Shifter: the ST screen JOUST draws into (32000 bytes, 16-pixel groups of
// four interleaved plane words, at $F8000) shown through the 16 colour
// registers, as one plane of palette indices -- once a host frame. No
// rasters: JOUST sets its palette with Setpalette / Setcolor only.
//
// Only the 16-pixel groups the game wrote since the last host frame are
// converted: the plane keeps palette indices, so a colour change is just the
// 16 registers, and the rest of the plane already holds what the ST screen
// holds. Every screen write goes through bus.zig (touch) or loadImage
// (touchAll). The game runs ~25 frames a second against a 60 Hz host and
// moves a few sprites a frame: most host frames convert nothing.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const State = @import("state.zig");

const LINE: usize = 160;
const LINES: usize = 200;
const GROUPS = LINE / 8; // 16 pixels: four plane words

/// A bit per 16-pixel group, a word per line: written since the last present().
var dirty: [LINES]u32 = @splat(0);

/// A write of n bytes at screen offset o (St.wr, inside the 32000 bytes): the
/// group of its first byte and of its last (a long can straddle two).
pub inline fn touch(o: u32, n: u8) void {
    if (n == 0) return;
    mark(o);
    mark(o + n - 1);
}

inline fn mark(o: u32) void {
    const y = o / LINE;
    dirty[y] |= @as(u32, 1) << @intCast((o - y * LINE) / 8);
}

/// The whole screen (a fresh image, or a fresh plane).
pub fn touchAll() void {
    @memset(&dirty, (1 << GROUPS) - 1);
}

/// One plane byte -> eight pixels, one byte lane each, MSB = leftmost pixel.
/// Shifting the result left by p puts the bit at plane p's weight.
const SPREAD: [256]u64 = blk: {
    @setEvalBranchQuota(4000);
    var t: [256]u64 = undefined;
    for (0..256) |b| {
        var v: u64 = 0;
        for (0..8) |k| v |= @as(u64, (b >> (7 - k)) & 1) << (8 * k);
        t[b] = v;
    }
    break :blk t;
};

pub fn present(pal: *const [16]u16, fb: *zg.LogicalFB) void {
    for (0..16) |i| fb.palette[i] = stColor(pal[i]);
    for (0..LINES) |y| {
        var bits = dirty[y];
        if (bits == 0) continue;
        dirty[y] = 0;
        const src = State.scr[State.BELOW + y * LINE ..][0..LINE];
        const dst = fb.fb[y * @as(usize, fb.stride) ..][0..zg.WIDTH];
        while (bits != 0) : (bits &= bits - 1) group(dst, src, @ctz(bits));
    }
}

/// 16 pixels: two passes of 8, the high bytes of the four plane words, then the low.
fn group(dst: *[zg.WIDTH]u8, src: *const [LINE]u8, gi: usize) void {
    inline for (0..2) |half| {
        const g = gi * 8 + half;
        const v = SPREAD[src[g]] | SPREAD[src[g + 2]] << 1 |
            SPREAD[src[g + 4]] << 2 | SPREAD[src[g + 6]] << 3;
        std.mem.writeInt(u64, dst[gi * 16 + half * 8 ..][0..8], v, .little);
    }
}

/// An ST colour register ($0RGB, three bits a gun) as the machine's RGBA.
pub fn stColor(word: u16) u32 {
    const r: u32 = gun(word >> 8);
    const g: u32 = gun(word >> 4);
    const b: u32 = gun(word);
    return (0xFF << 24) | (b << 16) | (g << 8) | r;
}

fn gun(nibble: u16) u32 {
    return @as(u32, nibble & 7) * 255 / 7;
}
