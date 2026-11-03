// --------------------------------------------------------------------------
// NATRIUM ZIG mode: what every ZIG effect shares, taken from zg.mem at the
// FIRST Z press (the default mode allocates nothing it did not before).
//
//   bg       400x280 chunky: the part's still picture where the overscan plane
//            shows it (the original's screen at (40, 40), black borders). The
//            env objects restore under themselves from it; the box parts take
//            the girl panel from it. Built once on entering a part.
//   skin, face, env  the original's textures (tex_skin, tex_face, env_tex)
//            with their levels moved to palette entries 16.. (SHADE0), where
//            the ZIG palette holds them as true colours: no dither.
//   scratch  one ST screen, to expand a picture that is not on screen.
// CHISEL reads all of it from cart RAM itself (SRC_ABS).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const A = @import("assets.zig");
const st = @import("st.zig");

pub const W: usize = zg.PHYSICAL_WIDTH; // 400
pub const H: usize = zg.PHYSICAL_HEIGHT; // 280
pub const OX: usize = zg.HORIZONTAL_BORDERS_WIDTH; // 40: the ST screen's place in the window
pub const OY: usize = zg.VERTICAL_BORDERS_HEIGHT; // 40
pub const TEX: usize = 128;
/// Palette entry of shade / level 0; entries 0..15 stay the ST palette.
pub const SHADE0: u8 = 16;

pub var bg: []u8 = &.{};
pub var skin: []u8 = &.{};
pub var face: []u8 = &.{};
pub var env: []u8 = &.{};
pub var scratch: *st.Screen = undefined;
pub var bl: zg.Blitter = .{};
/// CHISEL ops issued this frame (zig_api: the harness asserts a ceiling).
pub var ops: u32 = 0;

/// False when cart RAM is short (everything taken here is given back).
pub fn alloc() bool {
    const m = zg.mem.mark();
    bg = zg.mem.alloc(u8, W * H) orelse return fail(m);
    skin = zg.mem.alloc(u8, TEX * TEX) orelse return fail(m);
    face = zg.mem.alloc(u8, TEX * TEX) orelse return fail(m);
    env = zg.mem.alloc(u8, TEX * TEX) orelse return fail(m);
    const s = zg.mem.alloc(st.Screen, 1) orelse return fail(m);
    scratch = &s[0];
    for (skin, A.tex_skin) |*d, v| d.* = SHADE0 + v;
    for (face, A.tex_face) |*d, v| d.* = SHADE0 + v;
    for (env, A.env_tex) |*d, v| d.* = SHADE0 + v;
    bl.init();
    return true;
}

fn fail(m: zg.mem.Mark) bool {
    zg.mem.release(m);
    return false;
}

/// bg = the ST screen `s` (palette indices 0..15) at (OX, OY), black borders.
pub fn expandBg(s: *const st.Screen) void {
    @memset(bg, 0);
    st.toChunky(s, bg[OY * W + OX ..], W);
}

/// bg = an ILBM picture (a girl) alone, through the scratch screen.
pub fn pictureBg(body: []const u8) void {
    st.fromIlbm(scratch, body, 0, 200);
    expandBg(scratch);
}

/// Copy the w x h box at (x, y) of bg onto the plane, clipped to the window.
pub fn restore(fb: *zg.LogicalFB, x: i32, y: i32, w: i32, h: i32) void {
    const x0 = @max(x, 0);
    const y0 = @max(y, 0);
    const x1 = @min(x + w, @as(i32, W));
    const y1 = @min(y + h, @as(i32, H));
    if (x1 <= x0 or y1 <= y0) return;
    bl.blitImage(fb, @intCast(x0), @intCast(y0), bg, W, @intCast(x0), @intCast(y0), @intCast(x1 - x0), @intCast(y1 - y0), null);
    ops += 1;
}

/// The chunky box parts' girl panel ($C722 + its pen-15 borders): ST columns
/// x .. x + 97, all 200 lines, back over a full-screen effect.
pub fn panel(fb: *zg.LogicalFB, st_x: i32) void {
    restore(fb, @as(i32, OX) + st_x, OY, 98, 200);
}

pub const PANEL_P2: i32 = 207; // part 2: the panel's left border, group 12 bit 0
pub const PANEL_P7: i32 = 15; // part 7: group 0
