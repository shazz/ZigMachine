// --------------------------------------------------------------------------
// The logo's sway and shear. The original ($13A5C) copies each of the logo's 36
// lines, every frame, out of 16 preshifted 512-px copies at an x read from a
// 2816-word table ($14A2C): line L of frame n sits at x = 16 + T[(n + L) % 2816]
// (the table index advances one word a frame and one word a line). Both the
// sway (a slow drift of the whole logo) and the shear (neighbouring lines at
// different x) come out of that one table.
//
// No plane here can scroll per line with its borders open (an overscan plane
// reads no HSCROLL), so this does what the original does: one copy a line,
// from a padded copy of the logo in cart RAM (zeros either side, so a line is
// a single 320-px CHISEL copy with no clip and no clear). A line whose x did
// not change since last frame is not copied again.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const A = @import("assets.zig");

pub const ROWS = 36;
const LOGO_W = 288;
const AT = 320; // where the logo starts in a padded line
const PAD_W = AT + LOGO_W + 176; // sx = 304 - dx in [145, 463], plus 320: 784

/// The original copies the logo into the screen being DISPLAYED, starting ~24
/// lines down (Hatari: HBL 58), and the beam stays ahead of the copy: every
/// line on screen in frame n is still the copy loop n-2 made into that buffer.
pub const LAG = 2;

const padded: [PAD_W * ROWS]u8 = blk: {
    @setEvalBranchQuota(100_000);
    var out = [_]u8{0} ** (PAD_W * ROWS);
    for (0..ROWS) |r| {
        for (0..LOGO_W) |i| out[r * PAD_W + AT + i] = A.logo_raw[r * LOGO_W + i];
    }
    break :blk out;
};
const img = blit.Image.init(&padded, PAD_W);

var last_sx: [ROWS]u16 = undefined;

pub fn reset() void {
    @memset(&last_sx, 0xFFFF);
}

/// The table word of logo line `row` in frame n, sign-extended.
pub fn dx(n: u32, row: usize) i32 {
    const w = A.LOGO_DX[(n + row) % A.LOGO_DX.len];
    return @as(i16, @bitCast(w));
}

/// Screen x (0..319 is the ST screen) of logo line `row` in frame n.
pub fn x(n: u32, row: usize) i32 {
    return 16 + dx(n -| LAG, row);
}

pub fn draw(d: blit.Dst, n: u32) void {
    const screen = d.window(A.X0, A.Y0, 320, ROWS);
    for (0..ROWS) |r| {
        const sx: u16 = @intCast(AT - x(n, r));
        if (sx == last_sx[r]) continue;
        last_sx[r] = sx;
        blit.blit(screen, img, .{ .x = sx, .y = r, .w = 320, .h = 1 }, 0, @intCast(r), null, .copy);
    }
}
