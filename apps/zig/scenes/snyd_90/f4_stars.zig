// --------------------------------------------------------------------------
// F4's three star layers (31 stars each, at $FC2C / $FCA8 / $FD24, x and y
// in quarter... units of 4: x 0..$500, y 0..$320). A drift ($841E: four
// sine walkers, $F40C / $F80C) gives a speed and a direction a frame; the
// layers move at 1/4, 1/2 and 1x of it ($8346) and a star that leaves comes
// back at the far edge, at a random place ($8302 / $8320: x' = x * $6255 +
// $3619). They are plotted ($8282 / $82AA / $82D6: plane 0, plane 1, both)
// through the screen's line table ($F3DA) and the pixel table $103E0, and
// cleared from the lists of the frame before ($83E6 / $83FE).
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");

pub const LISTS = [3]u32{ 0xF3C2, 0xF3CA, 0xF3D2 }; // this screen's; +4 the other's
const LAYERS = [3]u32{ 0xFC2C, 0xFCA8, 0xFD24 };
const LINES: u32 = 0xF3DA;
const PIXELS: u32 = 0x103E0;
const SPEED_X: u32 = 0x84DA;
const SPEED_Y: u32 = 0x84D8;

/// $841E: the drift.
pub fn drift(r: *const st.Ram) void {
    const steps = [4]u16{ 6, 8, 4, 0xFFF6 };
    var w: [4]u32 = undefined;
    for (&w, steps, 0..) |*v, s, k| {
        const a = 0x8416 + 2 * @as(u32, @intCast(k));
        v.* = (r.w(a) +% s) & 0x3FE;
        r.sw(a, @intCast(v.*));
    }
    const x = r.w(0xF40C + w[0]) +% r.w(0xF40C + w[1]);
    const y = r.w(0xF80C + w[2]) +% r.w(0xF80C + w[3]);
    const dx = x -% r.w(0x84DC) -% 5;
    const dy = y -% r.w(0x84DE);
    r.sw(0x84DC, x);
    r.sw(0x84DE, y);
    speed(r, dx, SPEED_X, 0x84E0);
    speed(r, dy, SPEED_Y, 0x84E2);
}

fn speed(r: *const st.Ram, d: u16, at: u32, sign: u32) void {
    const neg = d & 0x8000 != 0;
    r.sw(sign, @intFromBool(neg));
    r.sw(at, if (neg) 0 -% d else d);
}

/// $83E6 / $83FE: clear the stars this screen showed (a word, or for the
/// two-plane layer a long).
pub fn clear(r: *const st.Ram) void {
    for (LISTS, 0..) |l, k| {
        const list = r.l(l);
        if (r.l(list) == 0) continue;
        for (0..31) |i| {
            const a = r.l(list + 4 * @as(u32, @intCast(i)));
            if (k == 2) r.sl(a, 0) else r.sw(a, 0);
        }
    }
}

/// $8346 for each layer, then $8282 / $82AA / $82D6.
pub fn move(r: *const st.Ram) void {
    const sx = r.w(SPEED_X);
    const sy = r.w(SPEED_Y);
    const dx = [3]u16{ (sx >> 2) << 2, (sx >> 1) << 2, sx << 2 };
    const dy = [3]u16{ (sy >> 2) << 2, (sy >> 1) << 2, sy << 2 };
    for (LAYERS, dx, dy) |layer, x, y| fly(r, layer, x, y);
    for (LAYERS, LISTS, 0..) |layer, list, k| plot(r, layer, r.l(list), k);
}

fn fly(r: *const st.Ram, layer: u32, dx0: u16, dy0: u16) void {
    const dx = if (r.w(0x84E0) == 1) 0 -% dx0 else dx0;
    const dy = if (r.w(0x84E2) == 1) 0 -% dy0 else dy0;
    for (0..31) |i| {
        const a = layer + 4 * @as(u32, @intCast(i));
        const x: i16 = @bitCast(r.w(a) +% dx);
        if (x >= 0x500) {
            r.sw(a, 0);
            r.sw(a + 2, rnd(r, 0x8342, 0xC8));
        } else if (x <= 0) {
            r.sw(a, 0x4FC);
            r.sw(a + 2, rnd(r, 0x8342, 0xC8));
        } else {
            r.sw(a, @bitCast(x));
            const y: i16 = @bitCast(r.w(a + 2) -% dy);
            if (y >= 0x320) {
                r.sw(a + 2, 0);
                r.sw(a, rnd(r, 0x833E, 0x140));
            } else if (y <= 0) {
                r.sw(a + 2, 0x31C);
                r.sw(a, rnd(r, 0x833E, 0x140));
            } else r.sw(a + 2, @bitCast(y));
        }
    }
}

/// $8302 / $8320 then `mulu #range; lsr #8; lsl #2`: a random multiple of 4.
fn rnd(r: *const st.Ram, seed: u32, range: u32) u16 {
    const v: u16 = @truncate(r.l(seed));
    const n: u32 = @as(u16, @truncate(@as(u32, @bitCast(@as(i32, @as(i16, @bitCast(v))) * 0x6255)) +% 0x3619));
    r.sl(seed, n);
    return @truncate((((n >> 8) * range) >> 8) << 2);
}

fn plot(r: *const st.Ram, layer: u32, list: u32, kind: usize) void {
    const lines = r.l(LINES);
    for (0..31) |i| {
        const a = layer + 4 * @as(u32, @intCast(i));
        const px = r.l(st.add(PIXELS, st.sx(r.w(a))));
        var at = st.add(r.l(st.add(lines, st.sx(r.w(a + 2)))), st.sx(@truncate(px)));
        if (kind == 1) at += 2;
        const bit: u16 = @truncate(px >> 16);
        r.sw(at, r.w(at) | bit);
        if (kind == 2) r.sw(at + 2, r.w(at + 2) | bit);
        r.sl(list + 4 * @as(u32, @intCast(i)), at);
    }
}
