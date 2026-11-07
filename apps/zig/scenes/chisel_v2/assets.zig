// --------------------------------------------------------------------------
// CHISEL v2 test cart: what the ops read, built once at init in the RAM arena
// (zg.mem: nothing in the cart binary). CHISEL reads them from cart RAM itself
// (SRC_ABS), the way a real cart keeps its textures and maps.
//   texture  128 x 128, a 16-colour XOR pattern with a border grid (indices 16..31)
//   tunnel   416 x 264 map, each pixel's (u = angle, v = 2048 / distance) around its
//            centre: the plane shows a 320 x 200 window of it, moved to bend the tunnel
//   sprite   16 x 16 arrow, asymmetric so every flip shows, 0 = transparent
// Float is used here only to build the tunnel map once (init, CLAUDE.md "Float
// math"); every per-frame number is integer.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");

pub const TEX: u16 = 128;
pub const BEND_X: i32 = 48; // how far the window (the tunnel's centre) may move
pub const BEND_Y: i32 = 32;
pub const MAP_W: u16 = 320 + 2 * BEND_X;
pub const MAP_H: u16 = 200 + 2 * BEND_Y;
pub const SPR: u16 = 16;
pub const SPR_COL: u8 = 40; // the sprite's inks: 40..43

pub const Assets = struct {
    tex: []u8 = &.{},
    map: []u16 = &.{},
    spr: []u8 = &.{},

    pub fn init(a: *Assets) bool {
        a.tex = zg.mem.alloc(u8, @as(usize, TEX) * TEX) orelse return false;
        a.map = zg.mem.alloc(u16, @as(usize, MAP_W) * MAP_H) orelse return false;
        a.spr = zg.mem.alloc(u8, @as(usize, SPR) * SPR) orelse return false;
        texture(a.tex);
        tunnel(a.map);
        arrow(a.spr);
        return true;
    }
};

fn texture(t: []u8) void {
    for (0..TEX) |v| for (0..TEX) |u| {
        const grid = u % 32 == 0 or v % 32 == 0;
        t[v * TEX + u] = if (grid) 31 else @intCast(16 + ((u >> 3) ^ (v >> 3)) % 15);
    };
}

fn tunnel(m: []u16) void {
    for (0..MAP_H) |y| for (0..MAP_W) |x| {
        const dx: f32 = @as(f32, @floatFromInt(x)) - @as(f32, @floatFromInt(160 + BEND_X));
        const dy: f32 = @as(f32, @floatFromInt(y)) - @as(f32, @floatFromInt(100 + BEND_Y));
        const r = @max(@sqrt(dx * dx + dy * dy), 1.0);
        const ang: u32 = @intFromFloat((std.math.atan2(dy, dx) / (2.0 * std.math.pi) + 1.0) * 256.0);
        const depth: u32 = @intFromFloat(@min(2048.0 / r, 65535.0));
        m[y * MAP_W + x] = @intCast(((depth & 0xFF) << 8) | (ang & 0xFF));
    };
}

fn arrow(s: []u8) void {
    for (0..SPR) |y| for (0..SPR) |x| {
        const shaft = y >= 6 and y < 10 and x < 10;
        const head = x >= 8 and @abs(@as(i32, @intCast(y)) - 8) <= @as(i32, @intCast(x)) - 8 and x < 16;
        const tail = y < 3 and x < 4; // an off-axis mark: up-down flips show
        s[y * SPR + x] = if (tail) SPR_COL + 3 else if (head) SPR_COL else if (shaft) SPR_COL + 1 + @as(u8, @intCast(x & 1)) else 0;
    };
}
