// --------------------------------------------------------------------------
// The Shifter: the ST screen JOUST draws into (32000 bytes, 16-pixel groups of
// four interleaved plane words, at $F8000) shown through the 16 colour
// registers, as one plane of palette indices -- once a host frame. No
// rasters: JOUST sets its palette with Setpalette / Setcolor only.
//
// Only the LINES the game wrote since the last host frame are converted: the
// plane keeps palette indices, so a colour change is just the 16 registers,
// and the plane's other lines already hold what the ST screen holds. Every
// screen write goes through St.wr (touch) or loadImage (touchAll). The game
// runs ~25 frames a second against a 60 Hz host, and moves a few sprites a
// frame: most host frames convert nothing, the rest a few dozen lines.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const State = @import("state.zig");

const LINE: usize = 160;
const LINES: usize = 200;
const WORDS = (LINES + 31) / 32;

/// One bit a line: written since the last present().
var dirty: [WORDS]u32 = @splat(0);

/// A write of n bytes at screen offset o (St.wr, inside the 32000 bytes).
pub fn touch(o: u32, n: u8) void {
    if (n == 0) return;
    const r0 = o / LINE;
    const r1 = (o + n - 1) / LINE;
    dirty[r0 >> 5] |= @as(u32, 1) << @intCast(r0 & 31);
    dirty[r1 >> 5] |= @as(u32, 1) << @intCast(r1 & 31);
}

/// The whole screen (a fresh image, or a fresh plane).
pub fn touchAll() void {
    @memset(&dirty, 0xFFFF_FFFF);
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
    const pixels = fb.fb[0 .. @as(usize, fb.stride) * LINES];
    for (0..WORDS) |w| {
        var bits = dirty[w];
        dirty[w] = 0;
        while (bits != 0) : (bits &= bits - 1) {
            const y = w * 32 + @ctz(bits);
            if (y < LINES) line(pixels[y * fb.stride ..][0..zg.WIDTH], y);
        }
    }
}

fn line(dst: []u8, y: usize) void {
    const src = State.scr[State.BELOW + y * LINE ..][0..LINE];
    // two passes of 8 pixels per group: the high bytes, then the low
    for (0..LINE / 4) |h| {
        const g = (h >> 1) * 8 + (h & 1);
        const v = SPREAD[src[g]] | SPREAD[src[g + 2]] << 1 |
            SPREAD[src[g + 4]] << 2 | SPREAD[src[g + 6]] << 3;
        std.mem.writeInt(u64, dst[h * 8 ..][0..8], v, .little);
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
