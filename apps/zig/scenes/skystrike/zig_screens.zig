// --------------------------------------------------------------------------
// ZIG mode's other screens -- the title and its credits, the difficulty
// menu, the briefings and the start of a mission, the verdicts, the
// newspaper, the hall of fame and its name entry: whatever the ST shows
// while the world is not in view. ORIGINAL shows them as the ST did, 320 x
// 200 on plane 0 with the borders shut.
//
// ZIG shows the same screen (the game's physic screen, sprites and fades
// included) filling the open-bordered 400 x 280 frame on the overlay plane:
// scaled by 5/4 to 400 x 250, nearest pixel (each fourth column and line
// doubled), and centred, with the 15 lines above and below it in the colour
// the screen's own top and bottom lines are mostly painted in, so the sky
// or the ground runs on to the frame's edge. Nothing is written to the game.
// --------------------------------------------------------------------------
const scr = @import("scr.zig");
const scroll = @import("zig_scroll.zig");

const W: usize = @intCast(scroll.WIN_W);
const H: usize = @intCast(scroll.WIN_H);
/// The scaled screen: 5/4 of 320 x 200.
pub const SW: usize = scr.W * 5 / 4;
pub const SH: usize = scr.H * 5 / 4;
pub const Y0: usize = (H - SH) / 2;
comptime {
    if (SW != W) @compileError("the scaled screen must be the frame's width");
}

/// The source column / line of scaled column / line i.
pub fn src(i: usize) usize {
    return i * 4 / 5;
}

/// The colour most of line y of the screen is painted in.
pub fn mostly(px: []const u8, y: usize) u8 {
    var n = [_]u16{0} ** 16;
    for (px[y * scr.W ..][0..scr.W]) |c| n[c & 15] += 1;
    var best: u8 = 0;
    for (n, 0..) |k, c| {
        if (k > n[best]) best = @intCast(c);
    }
    return best;
}

/// The physic screen into the overlay's 400 x 280 indices.
pub fn draw(ov: []u8) void {
    const p = scr.get(.physic);
    if (p.len == 0) return;
    @memset(ov[0 .. Y0 * W], mostly(p, 0));
    @memset(ov[(Y0 + SH) * W .. H * W], mostly(p, scr.H - 1));
    for (0..SH) |y| {
        const from = p[src(y) * scr.W ..][0..scr.W];
        const to = ov[(Y0 + y) * W ..][0..W];
        for (to, 0..) |*d, x| d.* = from[src(x)];
    }
}
