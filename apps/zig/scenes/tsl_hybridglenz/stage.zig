// --------------------------------------------------------------------------
// Everything screen.js draws that is not a glenz object, in its own order:
// the fill, the framed panel, the intro's spinning square, the three text
// overlays, the logo and the scroller bar.
//
// Layout is the remake's coordinates halved onto the measured 1x grid (a 1x row
// is 2x rows 2r+1, 2r+2), then shifted right by X_OFF to centre the 360-wide
// Amiga screen in the 400-wide overscan plane. The bar and the scroller run the
// FULL raster because on the hardware there is no edge for them to stop at.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const Blitter = zg.Blitter;
const Vec2 = zg.BlitVec2;
const LogicalFB = zg.LogicalFB;
const A = @import("assets.zig");

pub const PLANE_W: u16 = zg.PHYSICAL_WIDTH; // 400
pub const PLANE_H: u16 = zg.PHYSICAL_HEIGHT; // 280
pub const X_OFF: i16 = 20; // (400 - 360) / 2

/// mycanvas.quad(192,171,352,352) and quad(194,173,348,348), halved.
pub const PANEL_X: i16 = 96 + X_OFF;
pub const PANEL_Y: i16 = 85;
pub const PANEL_SIZE: u16 = 176;
pub const INNER_X: i16 = 97 + X_OFF;
pub const INNER_Y: i16 = 86;
pub const INNER_SIZE: u16 = 174;

/// The scroller bar (mycanvascroll, 720x40): 2 px white, 36 px '#660022', 2 px
/// white — halved, 1 + 18 + 1.
pub const BAR_H: u16 = 20;
pub const TEXT_DY: i16 = 4; // the remake draws the text at 517, the bar at 508

/// The spinning square is mycanvas2's white 352x352 quad about the canvas's
/// mid-handle (360,284); halved, that is these corners about (180,142).
const SQ_L: f32 = -84;
const SQ_T: f32 = -57;
const SQ_R: f32 = 92;
const SQ_B: f32 = 119;
pub const SQ_CX: f32 = 180 + @as(f32, X_OFF);
pub const SQ_CY: f32 = 142;

pub fn background(fb: *LogicalFB, bl: *Blitter) void {
    bl.fill(fb, 0, 0, PLANE_W, PLANE_H, A.BG);
}

/// The white frame and the panel the glenz objects OR into. The panel MUST be
/// index 0 before a single triangle lands on it.
pub fn panel(fb: *LogicalFB, bl: *Blitter) void {
    bl.fill(fb, PANEL_X, PANEL_Y, PANEL_SIZE, PANEL_SIZE, A.WHITE);
    bl.fill(fb, INNER_X, INNER_Y, INNER_SIZE, INNER_SIZE, A.PANEL);
}

/// mycanvas2.draw(mycanvas, 360 + square.x, 284, alpha, rot, size, size).
/// Canvas composes T . R . S, so the corner is scaled, then turned, then placed.
pub fn square(fb: *LogicalFB, bl: *Blitter, x: f32, rot_deg: f32, size: f32) void {
    const a = rot_deg * 3.14159265358979 / 180.0;
    const c = @cos(a) * size;
    const s = @sin(a) * size;
    const cx = SQ_CX + x;
    var p: [4]Vec2 = undefined;
    const rel = [4][2]f32{ .{ SQ_L, SQ_T }, .{ SQ_R, SQ_T }, .{ SQ_R, SQ_B }, .{ SQ_L, SQ_B } };
    for (&p, rel) |*out, r| out.* = .{
        .x = clamp(cx + r[0] * c - r[1] * s),
        .y = clamp(SQ_CY + r[0] * s + r[1] * c),
    };
    bl.triangle(fb, p[0], p[1], p[2], A.WHITE);
    bl.triangle(fb, p[0], p[2], p[3], A.WHITE);
}

/// The blitter clips, but @intFromFloat does not: at size 2.5 a corner is
/// 640 px out, and a bad tween value must not be undefined behaviour.
fn clamp(v: f32) i16 {
    return @intFromFloat(@round(@max(-8192.0, @min(8192.0, v))));
}

pub fn bar(fb: *LogicalFB, bl: *Blitter, y: i16) void {
    bl.fill(fb, 0, y, PLANE_W, 1, A.WHITE);
    bl.fill(fb, 0, y + 1, PLANE_W, BAR_H - 2, A.BAR);
    bl.fill(fb, 0, y + @as(i16, BAR_H) - 1, PLANE_W, 1, A.WHITE);
}

pub fn logo(fb: *LogicalFB, bl: *Blitter, pixels: []const u8) void {
    bl.blitImage(fb, X_OFF, 0, pixels, A.LOGO_W, 0, 0, A.LOGO_W, A.LOGO_H, A.KEY);
}

/// txt1/2/3 are stored as their bounding box; the remake draws them at (0,0).
pub fn text(fb: *LogicalFB, bl: *Blitter, pixels: []const u8, r: A.Rect) void {
    bl.blitImage(fb, r.x + X_OFF, r.y, pixels, r.w, 0, 0, r.w, r.h, A.KEY);
}
