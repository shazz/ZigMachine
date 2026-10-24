// --------------------------------------------------------------------------
// leonard on ONE plane: the picture, the 312 bobs and the scroller used three
// planes (each one enabled costs FRESCO a whole-frame pass on the board). All
// three palettes are opaque-or-transparent and use 4 + 3 + 1 colours, so they
// fit one palette; the bobs and the scroller are drawn over the picture in
// painter's order. The tables below remap the art's indices at COMPILE TIME:
//
//   merged 0      transparent (never on screen: the picture covers it each
//                 frame; Sprite keys a letter's 0 only while entry 0 has alpha 0)
//   merged 1..4   back_pal 0..3        back.raw  v -> v + 1
//   merged 5..7   ball_pal 1..3        ball.raw  0 stays (the key), v -> v + 4
//   merged 8      font_pal 1           font.raw  0 stays (the key), 1 -> 8
// --------------------------------------------------------------------------
const zg = @import("zigos");
const Color = zg.Color;

const dir = "../../assets/screens/leonard/";
const back_pal = zg.convertU8ArraytoColors(@embedFile(dir ++ "back_pal.dat"));
const ball_pal = zg.convertU8ArraytoColors(@embedFile(dir ++ "ball_pal.dat"));
const font_pal = zg.convertU8ArraytoColors(@embedFile(dir ++ "font_pal.dat"));

pub const BACK_BASE: u8 = 1;
pub const BALL_BASE: u8 = 4; // ball index 1 lands on 5
pub const FONT_INK: u8 = 8;

pub const palette: [256]Color = blk: {
    var p = [_]Color{.{ .r = 0, .g = 0, .b = 0, .a = 0 }} ** 256;
    for (0..4) |i| p[BACK_BASE + i] = back_pal[i];
    for (1..4) |i| p[BALL_BASE + i] = ball_pal[i];
    p[FONT_INK] = font_pal[1];
    break :blk p;
};

fn remap(comptime raw: []const u8, comptime f: fn (u8) u8) [raw.len]u8 {
    @setEvalBranchQuota(raw.len * 4 + 1000);
    var out: [raw.len]u8 = undefined;
    for (raw, 0..) |v, i| out[i] = f(v);
    return out;
}

fn backIdx(v: u8) u8 {
    if (v > 3) @compileError("back.raw uses only indices 0..3");
    return v + BACK_BASE;
}
fn ballIdx(v: u8) u8 {
    if (v > 3) @compileError("ball.raw uses only indices 0..3");
    return if (v == 0) 0 else v + BALL_BASE;
}
fn fontIdx(v: u8) u8 {
    if (v > 1) @compileError("font.raw uses only indices 0..1");
    return if (v == 0) 0 else FONT_INK;
}

pub const back: [64000]u8 align(4) = remap(@embedFile(dir ++ "back.raw"), backIdx);
pub const ball: [256]u8 align(4) = remap(@embedFile(dir ++ "ball.raw"), ballIdx);
pub const font: [2160]u8 align(4) = remap(@embedFile(dir ++ "font.raw"), fontIdx);

comptime {
    // The merge is only legal if no colour needed blending: every entry is
    // fully opaque or fully transparent, so stacking == painter's order.
    for ([_][256]Color{ back_pal, ball_pal, font_pal }) |pal| {
        for (pal) |c| if (c.a != 0 and c.a != 255) @compileError("partial alpha: planes cannot merge");
    }
    for (back_pal[0..4]) |c| if (c.a != 255) @compileError("picture must be opaque");
    for (ball_pal[1..4]) |c| if (c.a != 255) @compileError("bob inks must be opaque");
    if (font_pal[1].a != 255) @compileError("font ink must be opaque");
    if (ball_pal[0].a != 0 or font_pal[0].a != 0) @compileError("bob/font index 0 must be the key");
}
