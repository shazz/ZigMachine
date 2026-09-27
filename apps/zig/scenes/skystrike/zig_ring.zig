// --------------------------------------------------------------------------
// ZIG mode's ring: the 3 x 3 screens around the plane -- sectors cx-1..cx+1
// across, layers b..b+2 up (b = the live layer less one, never below the
// ground) -- held in the scroll plane's own VRAM buffer, which the hardware
// pans (zig_scroll.zig). So the ring IS what is shown: no copy per frame.
//
//   ring x  = (sector - (cx - 1)) * 320 + x         960 wide
//   ring y  = (b + 2 - layer) * 160 + y             3 x 160, the bottom row
//             176 (the ground's own last 16 lines), then black under the
//             ground as tall as the HUD band (panel + margin), which only
//             that band ever covers: 540 high
//
// A slot is drawn by the game's own line 1000 in a sandbox (zig_sandbox.zig).
// Crossing a sector or a layer moves the buffer by one slot (a memmove) and
// leaves the three newly exposed slots to draw, one a frame, nearest the
// view first -- long before they come into it: a sector is 320 wide and the
// window reaches 200 past the plane. A slot whose sector changes (a crater,
// a building lost, a base captured: its signature) is drawn again. The live
// slot shows the game's back screen itself (zig_view.copyLive), bar excepted.
// --------------------------------------------------------------------------
const std = @import("std");
const scr = @import("scr.zig");
const B = @import("basic.zig");
const sandbox = @import("zig_sandbox.zig");
const scroll = @import("zig_scroll.zig");
const V = @import("vars.zig");
const v = &V.v;

pub const SEC: i32 = 320;
pub const LAYER: i32 = 160;
pub const SECTORS: i32 = 51;
pub const WORLD_W: i32 = SECTORS * SEC;
pub const W: usize = 960;
/// The layer rows, the ground's 176 lines, and the HUD band's black.
pub const H: usize = 2 * 160 + LAST + @as(usize, @intCast(scroll.WIN_H - scroll.VIEW_H));
/// The ground's slot row keeps all 176 lines of its screen.
pub const LAST: usize = 176;
/// The bonus bar's box (hud.zig 734: box 14,2 to 306,12): HUD in ZIG.
pub const BAR_X0: usize = 14;
pub const BAR_X1: usize = 306;
pub const BAR_Y0: usize = 2;
pub const BAR_Y1: usize = 12;

const Slot = struct { ok: bool = false, sig: u32 = 0, frozen: sandbox.Frozen = .{} };

var slots: [3][3]Slot = [_][3]Slot{[_]Slot{.{}} ** 3} ** 3;
pub var buf: []u8 = &.{};
pub var cx: i32 = 0;
pub var b: i32 = 0;
pub var valid: bool = false;
/// For the harness: slots drawn, whole-ring rebuilds, one-slot shifts.
pub var drawn: u32 = 0;
pub var rebuilds: u32 = 0;
pub var shifts: u32 = 0;

pub fn wrapSec(s: i32) i32 {
    return @mod(s, SECTORS);
}

/// a - b across the wrapped world, in -WORLD_W/2 .. WORLD_W/2.
pub fn wrapDelta(d: i32) i32 {
    return @mod(d + @divTrunc(WORLD_W, 2), WORLD_W) - @divTrunc(WORLD_W, 2);
}

pub fn sectorOf(c: usize) i32 {
    return wrapSec(cx - 1 + @as(i32, @intCast(c)));
}
pub fn layerOf(r: usize) i32 {
    return b + 2 - @as(i32, @intCast(r));
}
/// A MOVER's sector number off the world's ends (spawned at sx - 3 (73),
/// wrapped -1 -> 400 and 50 -> 51 (255)) is the sector just past the end it
/// left (400 is -1), shown only beside that end.
pub fn seat(s: i32) i32 {
    return if (s >= 200) s - 401 else s;
}

pub fn colOf(s0: i32) ?usize {
    const s = seat(s0);
    const d = if (s < 0 or s >= SECTORS) s - cx + 1 else @mod(s - cx + 1, SECTORS);
    return if (d >= 0 and d <= 2) @intCast(d) else null;
}
pub fn rowOf(l: i32) ?usize {
    const r = b + 2 - l;
    return if (r >= 0 and r <= 2) @intCast(r) else null;
}
/// The world x of the ring's column 0, and the world y (layer al's line y
/// is -al * 160 + y) of its row 0.
pub fn leftWX() i32 {
    return @mod((cx - 1) * SEC, WORLD_W);
}
pub fn topWY() i32 {
    return -(b + 2) * LAYER;
}

pub fn frozenAt(r: usize, c: usize) sandbox.Frozen {
    return if (slots[r][c].ok) slots[r][c].frozen else .{};
}

pub fn invalidate() void {
    valid = false;
}

/// Follow the live screen: nothing, a shift of one slot, or a rebuild.
pub fn sync(sx: i32, al: i32) void {
    const nb = @max(0, al - 1);
    if (!valid) return rebuild(sx, nb);
    if (sx == cx and nb == b) return;
    const d = wrapDelta((sx - cx) * SEC);
    if (nb == b and (d == SEC or d == -SEC)) return shiftH(@divExact(d, SEC));
    if (sx == cx and (nb - b == 1 or nb - b == -1)) return shiftV(nb - b);
    rebuild(sx, nb);
}

fn rebuild(sx: i32, nb: i32) void {
    cx = sx;
    b = nb;
    @memset(buf, 0);
    for (&slots) |*row| for (row) |*s| {
        s.* = .{};
    };
    valid = true;
    rebuilds +%= 1;
    for (0..3) |r| for (0..3) |c| draw(r, c);
}

/// d = +1: the plane went right, everything moves one slot left.
fn shiftH(d: i32) void {
    for (0..H) |y| {
        const row = buf[y * W ..][0..W];
        if (d > 0) std.mem.copyForwards(u8, row[0..640], row[320..960]) else std.mem.copyBackwards(u8, row[320..960], row[0..640]);
    }
    for (&slots) |*row| {
        const o = row.*; // an array literal over itself would read what it just wrote
        row.* = if (d > 0) .{ o[1], o[2], .{} } else .{ .{}, o[0], o[1] };
    }
    cx = wrapSec(cx + d);
    shifts +%= 1;
}

/// db = +1: the base went up a layer, everything moves one slot down.
fn shiftV(db: i32) void {
    const L: usize = @intCast(LAYER);
    const span = (2 * L + LAST) * W;
    if (db > 0) std.mem.copyBackwards(u8, buf[L * W ..][0 .. span - L * W], buf[0 .. span - L * W]) else std.mem.copyForwards(u8, buf[0 .. span - L * W], buf[L * W ..][0 .. span - L * W]);
    const o = slots;
    slots = if (db > 0) .{ [_]Slot{.{}} ** 3, o[0], o[1] } else .{ o[1], o[2], [_]Slot{.{}} ** 3 };
    b += db;
    shifts +%= 1;
}

/// What a sector's line 1000 depends on: sky layers on nothing; the ground
/// on its type, its gun and building bits, its base, and the few globals the
/// screen builders read.
fn signature(s: i32, l: i32) u32 {
    if (l > 0) return 1;
    const parts = [_]i32{
        scr.peek(v.sc9 + s), scr.peek(v.ghx9 + s), scr.peek(v.lc9 + s), v.bse_a[B.ix(42, B.div(s, 10))],
        @intFromBool(s == v.main),   v.tsc, v.nght, v.btlsnk, v.carsnk, @intFromBool(s == v.tgtx), v.mission,
    };
    var h: u32 = 2166136261;
    for (parts) |p| h = (h ^ @as(u32, @bitCast(p))) *% 16777619;
    return h;
}

fn draw(r: usize, c: usize) void {
    const s = sectorOf(c);
    const l = layerOf(r);
    const f = sandbox.render(s, l);
    const src = sandbox.back();
    const lines: usize = if (r == 2) LAST else @intCast(LAYER);
    const y0 = r * @as(usize, @intCast(LAYER));
    for (0..lines) |y| @memcpy(buf[(y0 + y) * W + c * 320 ..][0..320], src[y * 320 ..][0..320]);
    slots[r][c] = .{ .ok = true, .sig = signature(s, l), .frozen = f };
    drawn +%= 1;
}

/// Draw what is missing: every slot the window (ring coords) touches, now;
/// of the rest, the nearest one.
pub fn pump(wx: i32, wy: i32, ww: i32, wh: i32) void {
    var best: ?[2]usize = null;
    var best_d: i32 = std.math.maxInt(i32);
    for (0..3) |r| for (0..3) |c| {
        const sl = &slots[r][c];
        if (sl.ok and sl.sig != signature(sectorOf(c), layerOf(r))) sl.ok = false;
        if (sl.ok) continue;
        const x0: i32 = @intCast(c * 320);
        const y0: i32 = @intCast(r * 160);
        if (x0 < wx + ww and x0 + SEC > wx and y0 < wy + wh and y0 + LAYER > wy) {
            draw(r, c);
            continue;
        }
        const d = @as(i32, @intCast(@abs(x0 + 160 - wx - @divTrunc(ww, 2)))) + @as(i32, @intCast(@abs(y0 + 80 - wy - @divTrunc(wh, 2))));
        if (d < best_d) {
            best_d = d;
            best = .{ r, c };
        }
    };
    if (best) |rc| draw(rc[0], rc[1]);
}
