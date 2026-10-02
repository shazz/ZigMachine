// --------------------------------------------------------------------------
// F4's ring of eleven white balls (16x16, two planes of colour, masked on
// all four). $84F4 places them on two sums of sines each ($16248 / $16648,
// four walkers stepping 4/-12/12/-4, the balls $28/$3C apart), through the
// screen's line table and the x table $108E0 (address offset and preshift);
// $85CA draws them, each from its own frame of an animation list ($1708C,
// pointers 8 bytes apart, the list's start one step on each frame, -1 =
// back to the start). $880E clears the balls this screen showed (16 lines,
// two groups, the list of the screen: $16A48 or $16BD8 by $F3C0).
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");

const LINES: u32 = 0xF3DA;
const PLACED: u32 = 0x17484; // (address.l, preshift offset.w) a ball
const ANIM: u32 = 0x17088;
const ANIM_START: u32 = 0x1708C;
const END: u32 = 0xFFFF_FFFF;

fn clearList(r: *const st.Ram) u32 {
    return if (r.w(0xF3C0) == 1) 0x16BD8 else 0x16A48;
}

/// $880E.
pub fn clear(r: *const st.Ram) void {
    const list = clearList(r);
    if (r.l(list) == 0) return;
    for (0..11) |i| {
        const a = r.l(list + 4 * @as(u32, @intCast(i)));
        for (0..16) |y| {
            r.sl(a + @as(u32, @intCast(y)) * st.LINE, 0);
            r.sl(a + @as(u32, @intCast(y)) * st.LINE + 8, 0);
        }
    }
}

/// $84F4.
pub fn place(r: *const st.Ram) void {
    const steps = [4]u16{ 4, 0xFFF4, 12, 0xFFFC };
    const apart = [4]u16{ 0x28, 0x3C, 0x3C, 0xFFD8 };
    var w: [4]u32 = undefined;
    for (&w, steps, 0..) |*v, s, k| {
        const a = 0x84E4 + 2 * @as(u32, @intCast(k));
        v.* = (r.w(a) +% s) & 0x3FE;
        r.sw(a, @intCast(v.*));
    }
    var out = clearList(r);
    var placed = PLACED;
    for (0..11) |_| {
        for (&w, apart) |*v, s| v.* = (v.* +% s) & 0x3FE;
        const x = r.w(0x16248 + w[0]) +% r.w(0x16248 + w[2]);
        const y = r.w(0x16648 + w[1]) +% r.w(0x16648 + w[3]);
        const px = r.l(st.add(0x108E0, st.sx(x)));
        const at = st.add(r.l(st.add(r.l(LINES), st.sx(y))), st.sx(@truncate(px)));
        r.sl(out, at);
        r.sl(placed, at);
        r.sw(placed + 4, @truncate(px >> 16));
        out += 4;
        placed += 6;
    }
}

/// $85CA.
pub fn draw(r: *const st.Ram) void {
    var a1 = r.l(ANIM);
    if (r.l(a1) == END) a1 = ANIM_START;
    a1 += 4;
    r.sl(ANIM, a1);
    var placed = PLACED;
    for (0..11) |_| {
        if (r.l(a1) == END) a1 = ANIM_START;
        const frame = st.add(r.l(a1), st.sx(r.w(placed + 4)));
        a1 += 8;
        ball(r, r.l(placed), frame);
        placed += 6;
    }
}

/// 16 rows, the right group then the left one: mask all four planes, OR
/// planes 0-1.
fn ball(r: *const st.Ram, at: u32, frame: u32) void {
    var src = frame;
    for (0..16) |y| {
        const row = at + @as(u32, @intCast(y)) * st.LINE;
        for ([2]u32{ 8, 0 }) |g| {
            const m = r.l(src);
            const d = r.l(src + 4);
            src += 8;
            r.sl(row + g + 4, r.l(row + g + 4) & m);
            r.sl(row + g, (r.l(row + g) & m) | d);
        }
    }
}
