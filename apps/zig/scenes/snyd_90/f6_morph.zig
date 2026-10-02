// --------------------------------------------------------------------------
// F6's script and morphs. $C004 walks a list of 20-byte steps ($C12E..
// $C21E, looping): a shape (or -1: keep it), three turning speeds, a place
// to glide to over 127 passes ($C120 -> $CC84, in 16.16 steps $C108), the
// step's length and a distance to ease towards one unit a pass ($C106 ->
// $C220). A new shape ($14670 set) starts a morph ($C25E): every point
// glides to its counterpart in the shape's list ($1463C: x, y, z words,
// $8000 ends it) over 127 passes, in 16.16 steps ($132D8); surplus points go
// to the shape's last one, and the count ($CC0A) shrinks at the end.
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");

const POINTS: u32 = 0x12F60;
const POINTS_END: u32 = 0x132D8; // 73 points
const STEPS: u32 = 0x132D8;
const COUNT: u32 = 0xCC0A;
const NEXT_COUNT: u32 = 0xCC0E;
const LEFT: u32 = 0xCC12;
const NEW_SHAPE: u32 = 0x14670;
const SHAPE: u32 = 0x12AE8;

/// $C25E.
pub fn morph(r: *const st.Ram) void {
    if (r.b(NEW_SHAPE) == 0) return glide(r);
    r.sb(NEW_SHAPE, 0);
    r.sw(LEFT, 0x7F);
    var a = r.l(COUNT);
    while (a < POINTS_END) : (a += 12) r.cp(a, a - 12, 12);
    var src = r.l(0x1463C + 4 * @as(u32, r.w(SHAPE)));
    var p = POINTS;
    var dst = STEPS;
    while (r.holds(src) and r.w(src) != 0x8000) : (src += 6) {
        for (0..3) |k| step(r, p + 4 * @as(u32, @intCast(k)), r.w(src + 2 * @as(u32, @intCast(k))), dst + 4 * @as(u32, @intCast(k)));
        p += 12;
        dst += 12;
    }
    r.sl(NEXT_COUNT, p);
    while (p < r.l(COUNT) and r.holds(p)) : (p += 12) {
        for (0..3) |k| step(r, p + 4 * @as(u32, @intCast(k)), r.w(src - 6 + 2 * @as(u32, @intCast(k))), dst + 4 * @as(u32, @intCast(k)));
        dst += 12;
    }
    if (r.l(NEXT_COUNT) >= r.l(COUNT)) r.sl(COUNT, r.l(NEXT_COUNT));
}

/// One coordinate's 16.16 step: (target - now) << 16 >> 7.
fn step(r: *const st.Ram, at: u32, target: u16, out: u32) void {
    const diff: u16 = 0 -% (r.w(at + 2) -% target);
    r.sl(out, @bitCast(@as(i32, @bitCast(@as(u32, diff) << 16)) >> 7));
}

/// $C352: one 128th of the way (all 73 points), then the count settles.
fn glide(r: *const st.Ram) void {
    const left = r.w(LEFT) -% 1;
    r.sw(LEFT, left);
    if (left & 0x8000 != 0) {
        r.sw(LEFT, 0);
        r.sl(COUNT, r.l(NEXT_COUNT));
        return;
    }
    for (0..219) |k| {
        const a = POINTS + 4 * @as(u32, @intCast(k));
        r.sl(a, swapAdd(r.l(a), r.l(STEPS + 4 * @as(u32, @intCast(k)))));
    }
}

/// `swap; add.l; swap`: the long keeps its integer in the low word.
fn swapAdd(v: u32, d: u32) u32 {
    const s = (v << 16 | v >> 16) +% d;
    return s << 16 | s >> 16;
}

/// $C004: the script.
pub fn script(r: *const st.Ram) void {
    const target = r.w(0xC106);
    const now = r.w(0xC220);
    if (target != now) r.sw(0xC220, if (@as(i16, @bitCast(target)) < @as(i16, @bitCast(now))) now -% 1 else now +% 1);
    const left = r.w(0xC128) -% 1;
    r.sw(0xC128, left);
    if (left & 0x8000 != 0) nextStep(r);
    glidePlace(r);
}

fn nextStep(r: *const st.Ram) void {
    const a = r.l(0xC12A);
    if (r.w(a) & 0x8000 == 0) {
        r.sw(SHAPE, r.w(a));
        r.sb(NEW_SHAPE, 0xFF);
    }
    r.cp(0xC222, a + 2, 6); // speeds
    r.cp(0xC120, a + 8, 6); // place
    r.sw(0xC128, r.w(a + 16));
    r.sw(0xC106, r.w(a + 18));
    r.sl(0xC12A, if (a + 0x14 >= 0xC21E) 0xC12E else a + 0x14);
    r.sw(0xC126, 0x7F);
    for (0..3) |k| {
        const kk: u32 = @intCast(k);
        const cur = r.w(0xCC84 + 2 * kk);
        r.sw(0xC114 + 4 * kk, cur);
        r.sw(0xC116 + 4 * kk, 0);
        const d: u32 = (@as(u32, r.w(0xC120 + 2 * kk) -% cur) & 0xFFFF) << 16;
        r.sl(0xC108 + 4 * kk, @bitCast(@as(i32, @bitCast(d)) >> 7));
    }
}

/// $C0D2: the place glides for 127 passes.
fn glidePlace(r: *const st.Ram) void {
    const left = r.w(0xC126) -% 1;
    r.sw(0xC126, left);
    if (left & 0x8000 != 0) return r.sw(0xC126, 0);
    for (0..3) |k| {
        const kk: u32 = @intCast(k);
        r.sl(0xC114 + 4 * kk, r.l(0xC114 + 4 * kk) +% r.l(0xC108 + 4 * kk));
        r.sw(0xCC84 + 2 * kk, r.w(0xC114 + 4 * kk));
    }
}
