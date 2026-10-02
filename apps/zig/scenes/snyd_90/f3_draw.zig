// --------------------------------------------------------------------------
// F3's drawing, on the screen being drawn ($1AA9E: $60000 / $70000), as the
// part's main loop ($180FA) and VBL ($1888E) do it:
//   erase  $18B1A: each of the 32 balls of two frames ago -- planes 0-1 of two
//          groups cleared on 16 lines -- and its reflection: plane 0 set back
//          to $FFFF (the water's colour) on 8 lines.
//   stars  $18E28: 260 stars, each a pointer into the $30000 table of (mask,
//          screen offset) pairs, advanced by the speed $19160 (a new one every
//          $11D frames from $1913E); the previous ones are cleared first.
//   balls  $1810E: the curve. Six byte-sine walkers ($1AAAE..) step once a
//          frame, then 32 balls each step copies of them ($1AADA..): x = $3C +
//          three sines, y = three sines (byte adds, wrapping), the ball
//          (16x16, planes 0-1, 16 preshifts at $1B58C, masks at $1BD8C) at
//          (x, y) and its reflection -- the mask only, 8 lines -- at line
//          $113 - y/2 in the water.
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");

pub const DRAW: u32 = 0x1AA9E; // the screen being drawn
const SAVED: u32 = 0x1AAAA; // where this frame's (ball, reflection) pairs go
const WALKERS: u32 = 0x1AAAE; // 6 walker pointers, then the 6 per-ball copies
const SPRITES: u32 = 0x1B58C;
const MASKS: u32 = 0x1BD8C;
const LINE = st.LINE;

/// The 16 rows of a ball: which of the 5 mask pairs each ANDs with.
const BALL_MASK = [16]u8{ 0, 1, 2, 3, 3, 4, 4, 4, 4, 4, 4, 3, 3, 2, 1, 0 };
/// The 8 rows of a reflection.
const REFL_MASK = [8]u8{ 0, 2, 3, 4, 4, 4, 3, 1 };

pub fn erase(r: *const st.Ram, list: u32) void {
    var a = list;
    for (0..32) |_| {
        const ball = r.l(a);
        for (0..16) |y| {
            r.sl(ball + @as(u32, @intCast(y)) * LINE, 0);
            r.sl(ball + @as(u32, @intCast(y)) * LINE + 8, 0);
        }
        const refl = r.l(a + 4);
        for (0..8) |y| {
            r.sw(refl + @as(u32, @intCast(y)) * LINE, 0xFFFF);
            r.sw(refl + @as(u32, @intCast(y)) * LINE + 8, 0xFFFF);
        }
        a += 8;
    }
}

const STAR_PTRS: u32 = 0x16000;
const STAR_SPEED: u32 = 0x19160;
const STAR_SAVED: u32 = 0x19162; // the erase list of the screen being drawn
const STAR_COUNT: u32 = 0x1915E;
const STAR_NEXT: u32 = 0x1915A;
const STAR_SPEEDS: u32 = 0x1913E;

pub fn stars(r: *const st.Ram) void {
    const saved = r.l(STAR_SAVED);
    for (0..260) |k| r.sw(r.l(saved + 4 * @as(u32, @intCast(k))), 0);
    const hi = r.l(DRAW) & 0xFFFF_0000;
    const speed = r.w(STAR_SPEED);
    for (0..260) |k| {
        const p = STAR_PTRS + 4 * @as(u32, @intCast(k));
        r.sw(p + 2, r.w(p + 2) +% speed);
        const t = r.l(p);
        const at = hi | r.w(t + 2);
        r.sw(at, r.w(at) | r.w(t));
        r.sl(saved + 4 * @as(u32, @intCast(k)), at);
    }
    r.sw(STAR_COUNT, r.w(STAR_COUNT) -% 1);
    if (r.w(STAR_COUNT) != 0) return;
    r.sw(STAR_COUNT, 0x11D);
    var a = r.l(STAR_NEXT);
    if (r.w(a) == 0xFFFF) a = STAR_SPEEDS;
    r.sw(STAR_SPEED, r.w(a));
    r.sl(STAR_NEXT, a + 2);
}

const Walk = struct { ptr: u32, step: u32, byte: bool };

/// The frame walkers ($1AAAE..): x, y, x, y, x, y.
const FRAME = [6]Walk{
    .{ .ptr = WALKERS, .step = 0x1AAC6, .byte = false },  .{ .ptr = WALKERS + 4, .step = 0x1AAC8, .byte = false },
    .{ .ptr = WALKERS + 8, .step = 0x1AACE, .byte = false }, .{ .ptr = WALKERS + 12, .step = 0x1AAD0, .byte = false },
    .{ .ptr = WALKERS + 16, .step = 0x1AAD6, .byte = true }, .{ .ptr = WALKERS + 20, .step = 0x1AAD7, .byte = true },
};
const COPY: u32 = 0x1AADA; // the ball walkers, copies of the frame ones
const BALL_X = [3]Walk{
    .{ .ptr = COPY, .step = 0x1AACA, .byte = false },
    .{ .ptr = COPY + 8, .step = 0x1AAD2, .byte = false },
    .{ .ptr = COPY + 16, .step = 0x1AAD8, .byte = true },
};
const BALL_Y = [3]Walk{
    .{ .ptr = COPY + 4, .step = 0x1AACC, .byte = false },
    .{ .ptr = COPY + 12, .step = 0x1AAD4, .byte = false },
    .{ .ptr = COPY + 20, .step = 0x1AAD9, .byte = true },
};

/// Step a walker -- add.w to the address's low word, or add.b to its low
/// byte: the address wraps inside its table -- and read its sine byte.
fn advance(r: *const st.Ram, w: Walk) u8 {
    const a = r.l(w.ptr);
    const n = if (w.byte)
        (a & 0xFFFF_FF00) | ((a +% r.b(w.step)) & 0xFF)
    else
        (a & 0xFFFF_0000) | ((a +% r.w(w.step)) & 0xFFFF);
    r.sl(w.ptr, n);
    return r.b(n);
}

fn sum(r: *const st.Ram, ws: []const Walk, start: u8) u8 {
    var v = start;
    for (ws) |w| v +%= advance(r, w);
    return v;
}

pub fn balls(r: *const st.Ram) void {
    for (FRAME, 0..) |w, k| {
        _ = advance(r, w);
        r.sl(COPY + 4 * @as(u32, @intCast(k)), r.l(w.ptr));
    }
    var saved = r.l(SAVED);
    for (0..32) |_| {
        const x = sum(r, &BALL_X, 0x3C);
        const y = sum(r, &BALL_Y, 0);
        const screen = r.l(DRAW);
        const col: u32 = (x & 0xF0) >> 1;
        const ball = screen + @as(u32, y) * LINE + col;
        const refl = screen + (0x113 - @as(u32, y >> 1)) * LINE + col;
        r.sl(saved, ball);
        r.sl(saved + 4, refl);
        saved += 8;
        draw(r, ball, refl, @as(u32, x & 15) << 7);
    }
}

/// $1826C: AND the masks, OR the ball's planes 0-1 (two groups a row); the
/// reflection only ANDs.
fn draw(r: *const st.Ram, ball: u32, refl: u32, shift: u32) void {
    const m = MASKS + shift;
    for (BALL_MASK, 0..) |k, y| andRow(r, ball + @as(u32, @intCast(y)) * LINE, m + 8 * @as(u32, k));
    for (REFL_MASK, 0..) |k, y| andRow(r, refl + @as(u32, @intCast(y)) * LINE, m + 8 * @as(u32, k));
    const s = SPRITES + shift;
    for (0..16) |y| {
        const at = ball + @as(u32, @intCast(y)) * LINE;
        const src = s + 8 * @as(u32, @intCast(y));
        r.sl(at, r.l(at) | r.l(src));
        r.sl(at + 8, r.l(at + 8) | r.l(src + 4));
    }
}

fn andRow(r: *const st.Ram, at: u32, mask: u32) void {
    r.sl(at, r.l(at) & r.l(mask));
    r.sl(at + 8, r.l(at + 8) & r.l(mask + 4));
}
