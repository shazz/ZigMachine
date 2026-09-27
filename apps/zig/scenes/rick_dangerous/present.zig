// --------------------------------------------------------------------------
// The Shifter: the screen at the video base ($70000 or $78000: 32000 bytes,
// 16-pixel groups of four interleaved plane words) shown through the 16
// colour registers, as one plane of palette indices, once a host frame. No
// rasters: the game sets its palette through the colour registers only (the
// fades), never per line.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const m = @import("ram.zig");
const game = @import("game.zig");

const LINE: usize = 160;
const LINES: usize = 200;

/// One plane byte -> eight pixels, one byte lane each, MSB = leftmost pixel.
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

pub fn present(fb: *zg.LogicalFB) void {
    for (0..16) |i| fb.palette[i] = stColor(game.pal[i]);
    const base = game.vbase;
    if (m.mem.len == 0 or base < 0 or base + 32000 > m.MEM_LEN) return; // before the first flip
    const scr = m.mem[@intCast(base)..][0 .. LINE * LINES];
    const pixels = fb.fb[0 .. @as(usize, fb.stride) * LINES];
    for (0..LINES) |y| {
        const src = scr[y * LINE ..][0..LINE];
        const dst = pixels[y * fb.stride ..][0..zg.WIDTH];
        for (0..LINE / 4) |h| { // 8 pixels: the high bytes, then the low, of each group
            const g = (h >> 1) * 8 + (h & 1);
            const v = SPREAD[src[g]] | SPREAD[src[g + 2]] << 1 |
                SPREAD[src[g + 4]] << 2 | SPREAD[src[g + 6]] << 3;
            std.mem.writeInt(u64, dst[h * 8 ..][0..8], v, .little);
        }
    }
}

/// An ST colour register ($0RGB, three bits a gun) as the machine's RGBA.
pub fn stColor(word: i64) u32 {
    const r: u32 = gun(word >> 8);
    const g: u32 = gun(word >> 4);
    const b: u32 = gun(word);
    return (0xFF << 24) | (b << 16) | (g << 8) | r;
}

fn gun(nibble: i64) u32 {
    return @as(u32, @intCast(nibble & 7)) * 255 / 7;
}
