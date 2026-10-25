// --------------------------------------------------------------------------
// Union intro -- zg.palette.scaleRange without float: entries lo..=hi of a plane
// as the BASE palette's RGB times k, truncated, alpha 255, where k is an f32 held
// by f32emu.zig (the TRSI and placement fades keep their alpha that way since
// 2026-10-25). Each channel is fl(c * k) rounded as the f32 product was: the same
// colours as the f32 scaleRange, with no float a frame on ZIGGY.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const Color = zg.Color;
const emu = @import("f32emu.zig");

pub fn scaleRange(fb: *zg.LogicalFB, base: []const Color, lo: u8, hi: u8, k: emu.Value) void {
    const kk = @min(k, emu.ONE); // scale's clamp to [0, 1]
    var i: usize = lo;
    while (i <= hi) : (i += 1) {
        const c = base[i];
        fb.setPaletteEntry(@intCast(i), .{ .r = channel(c.r, kk), .g = channel(c.g, kk), .b = channel(c.b, kk), .a = 255 });
    }
}

fn channel(v: u8, k: emu.Value) u8 {
    return @intCast(emu.int(emu.mul(k, v)));
}
