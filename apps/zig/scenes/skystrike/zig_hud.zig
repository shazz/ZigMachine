// --------------------------------------------------------------------------
// ZIG mode's HUD, and the mode's notice.
//
// The game draws its panel (lines 176-199: score, fuel, planes, kills, the
// target arrow, the pilot's card) and its bonus bar (the box at 14,2 to
// 306,12) into the back screen as it always has; ZIG shows those pixels as
// they are, fixed in the frame while the world scrolls under them: the panel
// centred in the bottom border, black either side, with a margin of black
// under it that a monitor's frame may cover; the bar in the top border,
// moved down by the same kind of margin (zig_settings.zig).
//
// The notice ("ZIG MODE" / "ORIGINAL MODE") is written in the game's own
// 8x8 font on plane 3, a plain 320 x 200 plane of its own over whichever
// view is up, for NOTICE_VBLS frames after the switch. The game's screens
// are never written to.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const scr = @import("scr.zig");
const assets = @import("assets.zig");
const ring = @import("zig_ring.zig");
const scroll = @import("zig_scroll.zig");
const overlay = @import("zig_overlay.zig");
const set = @import("zig_settings.zig");
const V = @import("vars.zig");
const v = &V.v;

const W: usize = @intCast(scroll.WIN_W);
const H: usize = @intCast(scroll.WIN_H);
const PANEL_Y: usize = 176;
const PANEL_H: usize = @intCast(scroll.PANEL_H);
/// The panel's first line in the frame (right under the world's view), and
/// its left edge.
pub const HUD_Y: usize = @intCast(scroll.VIEW_H);
pub const HUD_X: usize = @intCast(@as(i32, @intCast((W - scr.W) / 2)) + set.hud_x_shift);
/// The bar keeps its columns on the ST screen, centred in the 400-wide frame
/// (the panel's sideways shift is its own), and moves down by the margin.
pub const BAR_DX: usize = (W - scr.W) / 2;
pub const BAR_DY: usize = set.bar_top_margin;
comptime {
    if (H - (HUD_Y + PANEL_H) < set.hud_bottom_margin) @compileError("the HUD panel is inside the bottom margin");
}

pub const NOTICE_PLANE = 3;
const NOTICE_FRAMES: u32 = set.notice_frames;
const NOTICE_Y: usize = set.notice_y;
const NOTICE_PEN: u8 = 15;
var notice_left: u32 = 0;
var notice_zig: bool = false;

/// The ammo counter, ZIG's own: in the band's black right of the panel.
pub const AMMO_X: usize = HUD_X + scr.W + 4;

pub fn draw(ov: []u8, pen: u8) void {
    panel(ov);
    text(ov, W, AMMO_X, HUD_Y + 3, "AMMO", pen, 0);
    const a: usize = @intCast(@max(0, @min(999, v.ammo)));
    const digits = [4]u8{ ' ', '0' + @as(u8, @intCast(a / 100)), '0' + @as(u8, @intCast(a / 10 % 10)), '0' + @as(u8, @intCast(a % 10)) };
    text(ov, W, AMMO_X, HUD_Y + 13, &digits, pen, 0);
}

fn panel(ov: []u8) void {
    const back = scr.get(.back);
    @memset(ov[HUD_Y * W .. H * W], 0);
    for (0..PANEL_H) |y| {
        const row = ov[(HUD_Y + y) * W ..][0..W];
        @memcpy(row[HUD_X..][0..scr.W], back[(PANEL_Y + y) * scr.W ..][0..scr.W]);
    }
    for (ring.BAR_Y0..ring.BAR_Y1 + 1) |y| {
        const n = ring.BAR_X1 + 1 - ring.BAR_X0;
        @memcpy(ov[(y + BAR_DY) * W + BAR_DX + ring.BAR_X0 ..][0..n], back[y * scr.W + ring.BAR_X0 ..][0..n]);
    }
}

/// The switch was made: show which mode for a while.
pub fn notice(zig: bool) void {
    notice_zig = zig;
    notice_left = NOTICE_FRAMES;
}

/// Once a frame, whatever the view.
pub fn tickNotice(zigos: *zg.ZigOS) void {
    const p = &zigos.lfbs[NOTICE_PLANE];
    if (notice_left == 0) {
        p.is_enabled = false;
        return;
    }
    notice_left -= 1;
    const px = p.fb[0 .. scr.W * scr.H];
    @memset(px, overlay.CLEAR);
    const msg: []const u8 = if (notice_zig) " ZIG MODE " else " ORIGINAL MODE ";
    const x0 = (scr.W - msg.len * 8) / 2;
    text(px, scr.W, x0, NOTICE_Y, msg, NOTICE_PEN, 0);
    p.is_enabled = true;
}

/// The game's 8x8 font (text.zig's) into a buffer `stride` pixels a row:
/// `pen` on `paper`, or on what is there when paper is null.
pub fn text(px: []u8, stride: usize, x: usize, y: usize, s: []const u8, pen: u8, paper: ?u8) void {
    for (s, 0..) |c, k| {
        const g = assets.FONT[@as(usize, if (c < 32) 0 else c - 32) * 8 ..][0..8];
        for (0..8) |j| for (0..8) |i| {
            const at = (y + j) * stride + x + k * 8 + i;
            if (g[j] >> @intCast(7 - i) & 1 != 0) px[at] = pen else if (paper) |p| px[at] = p;
        };
    }
}
