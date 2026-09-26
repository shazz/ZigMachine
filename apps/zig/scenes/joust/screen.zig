// --------------------------------------------------------------------------
// The Shifter: the ST screen JOUST draws into (32000 bytes, 16-pixel groups of
// four interleaved plane words, at $F8000) shown through the 16 colour
// registers, as one plane of palette indices -- once a host frame. No
// rasters: JOUST sets its palette with Setpalette / Setcolor only.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const State = @import("state.zig");

const LINE: usize = 160;
const LINES: usize = 200;

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
    const scr = State.scr[State.BELOW..];
    const pixels = fb.fb[0 .. @as(usize, fb.stride) * LINES];
    for (0..LINES) |y| {
        const src = scr[y * LINE ..][0..LINE];
        const dst = pixels[y * fb.stride ..][0..zg.WIDTH];
        // two passes of 8 pixels per group: the high bytes, then the low
        for (0..LINE / 4) |h| {
            const g = (h >> 1) * 8 + (h & 1);
            const v = SPREAD[src[g]] | SPREAD[src[g + 2]] << 1 |
                SPREAD[src[g + 4]] << 2 | SPREAD[src[g + 6]] << 3;
            std.mem.writeInt(u64, dst[h * 8 ..][0..8], v, .little);
        }
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
