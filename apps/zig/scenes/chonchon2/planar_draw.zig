// --------------------------------------------------------------------------
// The planar Clock's two drawing primitives, from internal/source/clock.go:
// the sliding panels' 16-byte row copies (twice, 80 bytes apart) and the
// ribbon's one-pixel 4-plane write. Only the REFERENCE clock (Clock, planar =
// true) draws with them; the live cart blits the same picture (compose.zig).
// --------------------------------------------------------------------------
const assets = @import("assets.zig");

pub fn panel(screen: *[32000]u8, y: i32, rows: i32, shift: usize) void {
    var panel_row: i32 = 0;
    while (panel_row <= rows) : (panel_row += 1) {
        const yy = y + panel_row;
        if (yy < 0 or yy >= 69) continue;
        const src = @as(usize, @intCast(yy)) * 160 + shift * 16;
        const dst = @as(usize, @intCast(yy)) * 160 + 0x200;
        var k: usize = 0;
        while (k < 16) : (k += 1) {
            if (src + k < assets.panel_pattern.len and dst + k < screen.len)
                screen[dst + k] = assets.panel_pattern[src + k];
            if (src + k < assets.panel_pattern.len and dst + 80 + k < screen.len)
                screen[dst + 80 + k] = assets.panel_pattern[src + k];
        }
    }
}

pub fn pixel(screen: *[32000]u8, x: usize, y: usize, v: u8) void {
    const at = y * 160 + x / 16 * 8;
    const mask: u16 = @as(u16, 1) << @intCast(15 - x % 16);
    var p: usize = 0;
    while (p < 4) : (p += 1) {
        const o = at + p * 2;
        var w = assets.beWord(screen, o);
        w = w & ~mask;
        if (v >> @intCast(p) & 1 != 0) w |= mask;
        screen[o] = @truncate(w >> 8);
        screen[o + 1] = @truncate(w);
    }
}
