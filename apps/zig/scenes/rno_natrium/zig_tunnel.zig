// --------------------------------------------------------------------------
// NATRIUM ZIG mode, part 2: the $DDEC tunnel over the whole overscan window,
// one CHISEL MAP op a frame (+ the hole and the girl panel: 3 ops).
//
// The original reads an 80x80-cell window (2x2-pixel cells, 7 dithered shades)
// out of a 160x100 offset table, ~1.1 VBL a call. Here the same tunnel
// (zig_math.tunnelEntry: the table's own formula, at one entry a PIXEL) is a
// 600x360 map built once at the first Z press, and a frame is:
//   pan     the original's xpan (SIN[3f]) and ypan (SIN[4f]) move the centre
//           +-100 / +-40 px: the map is read from (ox, oy), a slice of it
//   scroll  texel offsets u + f/2, v + f, the original's per-frame base
//   hole    the table's 0 entries (r < 16 px) read black in the original; MAP
//           draws every pixel, so a keyed 32x32 black disc covers them
// f is the part's VBL count with the frame's fraction (Q10, zig_mode.zig), so
// the pan moves every host frame instead of every 1.1 VBL.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const trig = zg.fixtrig;
const v2 = zg.chisel_v2;
const zmx = @import("rom_sdk").zmx;
const M = @import("zig_math.zig");
const R = @import("zig_res.zig");

pub const PX: i32 = 100; // the pan's half-ranges in pixels
pub const PY: i32 = 40;
pub const MW: usize = R.W + 2 * PX; // 600
pub const MH: usize = R.H + 2 * PY; // 360
const DISC: usize = 32;
const KEY: u8 = 255;

pub var map: []u16 = &.{};
var disc: []u8 = &.{};
/// The last frame's read origin in the map (zig_api).
pub var ox: u32 = 0;
pub var oy: u32 = 0;

/// The map (one quadrant computed, three mirrored) and the hole's disc.
pub fn build() bool {
    map = zg.mem.alloc(u16, MW * MH) orelse return false;
    disc = zg.mem.alloc(u8, DISC * DISC) orelse return false;
    for (0..MH / 2) |j| for (0..MW / 2) |i| {
        const e = M.tunnelEntry(@as(i32, @intCast(2 * i + 1)) - @as(i32, MW), @as(i32, @intCast(2 * j + 1)) - @as(i32, MH));
        const u: u16 = e & 127;
        const v: u16 = e & 0x7F00;
        // x mirrored: angle -> pi - angle; y mirrored: -angle; both: + pi
        const mx = if (e == 0) 0 else v | ((64 -% u) & 127);
        const my = if (e == 0) 0 else v | ((128 - u) & 127);
        const mxy = if (e == 0) 0 else v | ((u + 64) & 127);
        map[j * MW + i] = e;
        map[j * MW + MW - 1 - i] = mx;
        map[(MH - 1 - j) * MW + i] = my;
        map[(MH - 1 - j) * MW + MW - 1 - i] = mxy;
    };
    for (0..DISC) |b| for (0..DISC) |a| {
        const dx: i32 = @as(i32, @intCast(2 * a + 1)) - DISC;
        const dy: i32 = @as(i32, @intCast(2 * b + 1)) - DISC;
        disc[b * DISC + a] = if (@as(u32, @intCast(dx * dx + dy * dy)) < M.HOLE_R2) 0 else KEY;
    };
    return true;
}

/// The pan for time t (Q10 VBLs): the map's read origin.
pub fn panAt(t: u32) [2]u32 {
    const x = PX + zmx.zmMulsh16(trig.sin(t *% (3 << 12)), PX);
    const y = PY + zmx.zmMulsh16(trig.sin(t *% (4 << 12)), PY);
    return .{ @intCast(@min(@max(x, 0), 2 * PX)), @intCast(@min(@max(y, 0), 2 * PY)) };
}

pub fn draw(fb: *zg.LogicalFB, t: u32) void {
    const p = panAt(t);
    ox = p[0];
    oy = p[1];
    const tex = v2.Texture{ .pixels = R.skin, .stride = R.TEX, .umask = R.TEX - 1, .vmask = R.TEX - 1 };
    const uoff: u16 = @intCast((t >> 11) & 127);
    const voff: u16 = @intCast((t >> 10) & 127);
    v2.map(fb, tex, 0, 0, R.W, R.H, map[oy * MW + ox ..], MW, uoff, voff, .{});
    R.ops += 1;
    // the hole: the centre lies between map entries MW/2 - 1 and MW/2
    const cx: i32 = @as(i32, MW / 2) - @as(i32, @intCast(ox));
    const cy: i32 = @as(i32, MH / 2) - @as(i32, @intCast(oy));
    R.bl.blitImage(fb, @intCast(cx - DISC / 2), @intCast(cy - DISC / 2), disc, DISC, 0, 0, DISC, DISC, KEY);
    R.ops += 1;
    R.panel(fb, R.PANEL_P2);
}
