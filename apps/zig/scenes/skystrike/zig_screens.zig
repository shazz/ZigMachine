// --------------------------------------------------------------------------
// ZIG mode's other screens -- whatever the ST shows while the world is not
// in view -- in the open-bordered 400 x 280 frame on the overlay plane.
// ORIGINAL shows them as the ST did, 320 x 200 on plane 0, borders shut.
//
// What the physic screen holds decides how (hooks.screen, told by the game's
// code as it changes):
//   scene    the title, the menu, a briefing: a world scene, shown 1:1 with
//            the world extended into the left, right and top borders, the
//            title's scroller in the bottom one (zig_intro.zig,
//            zig_scroller.zig)
//   hall     the hall of fame and its name entry: the picture scaled by 5/4,
//            the text over it 1:1 (zig_hall.zig)
//   picture  anything else (the newspaper, the error trap, the moments a
//            screen is being built behind a fade): 1:1, the borders in the
//            colour most of the picture's own edge is painted in
// Nothing is written to the game.
// --------------------------------------------------------------------------
const scr = @import("scr.zig");
const hooks = @import("zig_hooks.zig");
const intro = @import("zig_intro.zig");
const hall = @import("zig_hall.zig");
const scroller = @import("zig_scroller.zig");
const scroll = @import("zig_scroll.zig");
const set = @import("zig_settings.zig");

const W: usize = @intCast(scroll.WIN_W);
const H: usize = @intCast(scroll.WIN_H);
/// The scaled picture: 5/4 of 320 x 200.
pub const SW: usize = scr.W * 5 / 4;
pub const SH: usize = scr.H * 5 / 4;
pub const Y0: usize = (H - SH) / 2;
comptime {
    if (SW != W) @compileError("the scaled screen must be the frame's width");
    if (set.screen_x + scr.W > W or set.screen_y + scr.H > H) @compileError("the screen must fit the frame");
}

/// Once per cart load, from zg.mem.
pub fn alloc() void {
    intro.alloc();
    hall.alloc();
}

/// The screen off the world into the overlay's 400 x 280 indices.
pub fn draw(ov: []u8) void {
    const p = scr.get(.physic);
    if (p.len == 0) return;
    switch (hooks.screen) {
        .scene => {
            intro.draw(ov);
            scroller.draw(ov, intro.H, mostly(p, scr.H - 1));
        },
        .hall => hall.draw(ov),
        .picture => picture(ov, p),
    }
}

/// 1:1 at screen_x, screen_y on the colour of its edge.
fn picture(ov: []u8, p: []const u8) void {
    @memset(ov[0 .. W * H], edge(p));
    for (0..scr.H) |y| @memcpy(ov[(set.screen_y + y) * W + set.screen_x ..][0..scr.W], p[y * scr.W ..][0..scr.W]);
}

/// The colour most of a picture's outermost lines and columns are.
fn edge(p: []const u8) u8 {
    var n = [_]u16{0} ** 16;
    for (0..scr.W) |x| {
        n[p[x] & 15] += 1;
        n[p[(scr.H - 1) * scr.W + x] & 15] += 1;
    }
    for (0..scr.H) |y| {
        n[p[y * scr.W] & 15] += 1;
        n[p[y * scr.W + scr.W - 1] & 15] += 1;
    }
    return most(&n);
}

fn most(n: *const [16]u16) u8 {
    var best: u8 = 0;
    for (n, 0..) |k, c| {
        if (k > n[best]) best = @intCast(c);
    }
    return best;
}

/// The source column / line of scaled column / line i.
pub fn src(i: usize) usize {
    return i * 4 / 5;
}

/// The colour most of line y of a picture is painted in.
pub fn mostly(px: []const u8, y: usize) u8 {
    var n = [_]u16{0} ** 16;
    for (px[y * scr.W ..][0..scr.W]) |c| n[c & 15] += 1;
    return most(&n);
}

/// A 320 x 200 picture scaled by 5/4 to 400 x 250, nearest pixel (each
/// fourth column and line doubled), centred; the 15 lines above and below it
/// in the colour most of its top / bottom line is, so the sky or the ground
/// runs on to the frame's edge.
pub fn scaled(ov: []u8, p: []const u8) void {
    @memset(ov[0 .. Y0 * W], mostly(p, 0));
    @memset(ov[(Y0 + SH) * W .. H * W], mostly(p, scr.H - 1));
    for (0..SH) |y| {
        const to = ov[(Y0 + y) * W ..][0..W];
        // Every fourth source line is shown twice: copy the line just made.
        if (y > 0 and src(y) == src(y - 1)) {
            @memcpy(to, ov[(Y0 + y - 1) * W ..][0..W]);
            continue;
        }
        widen(to, p[src(y) * scr.W ..][0..scr.W]);
    }
}

/// One line, 320 -> 400: each 4 source pixels to 5, the first doubled
/// (src() of 5g..5g+4 is 4g, 4g, 4g+1, 4g+2, 4g+3).
fn widen(to: *[W]u8, from: *const [scr.W]u8) void {
    for (0..scr.W / 4) |g| {
        const f = from[g * 4 ..][0..4];
        to[g * 5 ..][0..5].* = .{ f[0], f[0], f[1], f[2], f[3] };
    }
}
