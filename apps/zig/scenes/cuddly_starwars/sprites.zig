// --------------------------------------------------------------------------
// "THE UNION" (cuddly_starwars.zig, go() step 5): 8 sprites walking a recorded
// path (tables.zig) with a sine wobble, each a radian of phase behind the last.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const tables = @import("tables.zig");
const fixed = @import("fixed.zig");
const assert = std.debug.assert;

const W: usize = zg.WIDTH;
const H: usize = zg.HEIGHT;

const SPRITES: usize = 8;
const SPRITE_W: usize = 16;
const SPRITE_H: usize = 10;
const SPRITE_STRIP_W: usize = 128;
const SPRITE_SPACING: usize = 5; // db
const SPRITE_GAP_FROM: usize = 3; // "THE" + gap + "UNION"
const WOBBLE_X: i64 = 10;
const WOBBLE_Y: i64 = 5;
const WOBX_C = fixed.q30(@cos(0.07));
const WOBX_S = fixed.q30(@sin(0.07));
const WOBY_C = fixed.q30(@cos(0.09));
const WOBY_S = fixed.q30(@sin(0.09));
// sprite i adds a phase of i radians: sin(a + i) = sin a cos i + cos a sin i
const PHASE_C = blk: {
    var t: [SPRITES]i32 = undefined;
    for (0..SPRITES) |i| t[i] = fixed.q30(@cos(@as(f64, @floatFromInt(i))));
    break :blk t;
};
const PHASE_S = blk: {
    var t: [SPRITES]i32 = undefined;
    for (0..SPRITES) |i| t[i] = fixed.q30(@sin(@as(f64, @floatFromInt(i))));
    break :blk t;
};
const ROTOR_ZERO = fixed.Rotor{ .c = 1 << 30, .s = 0 };

const sprite_b = @embedFile("../../assets/screens/cuddly_starwars/sprite.raw");

comptime {
    assert(sprite_b.len == SPRITE_STRIP_W * SPRITE_H);
    assert(tables.sprite_x.len == tables.sprite_y.len);
}

pub const Sprites = struct {
    step_n: usize, // sC
    wob_x: fixed.Rotor, // sin/cos of sC * 0.07
    wob_y: fixed.Rotor, // sin/cos of sC * 0.09

    pub const init = Sprites{ .step_n = 0, .wob_x = ROTOR_ZERO, .wob_y = ROTOR_ZERO };

    pub fn step(self: *Sprites) void {
        self.step_n += 1;
        self.wob_x.turn(WOBX_C, WOBX_S);
        self.wob_y.turn(WOBY_C, WOBY_S);
        if (self.step_n > tables.sprite_x.len) self.* = init;
    }

    pub fn draw(self: *const Sprites, screen: []u8) void {
        const sx: i64 = self.wob_x.s;
        const cx: i64 = self.wob_x.c;
        const sy: i64 = self.wob_y.s;
        const cy: i64 = self.wob_y.c;
        for (0..SPRITES) |i| {
            const gap: usize = if (i >= SPRITE_GAP_FROM) SPRITE_SPACING else 0;
            // the path array is pushed onto itself: indexing past its end wraps
            const at = (self.step_n + i * SPRITE_SPACING + gap) % tables.sprite_x.len;
            // drawn at sub-pixel positions in the original; nearest pixel here (Math.round)
            const pc: i64 = PHASE_C[i];
            const ps: i64 = PHASE_S[i];
            const wx = (sx * pc + cx * ps) >> 30; // sin(step * 0.07 + i), Q30
            const wy = (cy * pc - sy * ps) >> 30; // cos(step * 0.09 + i), Q30
            const x = ((@as(i64, tables.sprite_x[at]) << 30) + WOBBLE_X * wx + (1 << 29)) >> 30;
            const y = ((@as(i64, tables.sprite_y[at]) << 30) + WOBBLE_Y * wy + (1 << 29)) >> 30;
            blitSprite(screen, (SPRITES - 1 - i) * SPRITE_W, @intCast(x), @intCast(y));
        }
    }
};

fn blitSprite(screen: []u8, part_x: usize, x: i32, y: i32) void {
    for (0..SPRITE_H) |r| {
        const py = y + @as(i32, @intCast(r));
        if (py < 0 or py >= H) continue;
        const src = sprite_b[r * SPRITE_STRIP_W + part_x ..][0..SPRITE_W];
        for (src, 0..) |s, c| {
            const px = x + @as(i32, @intCast(c));
            if (s == 0 or px < 0 or px >= W) continue;
            screen[@as(usize, @intCast(py)) * W + @as(usize, @intCast(px))] = s;
        }
    }
}
