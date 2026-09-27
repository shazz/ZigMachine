// --------------------------------------------------------------------------
// TCB #2's AN COOL / WIZ CODERS logo, $9964: a 608x25 strip in 16 preshifts
// at $57D80 (planes 1-3), of which 19 16-pixel groups show. Its lines each
// have their own x, from a 25-entry ring ($A3AA) fed one a frame by a script
// of positions (lists of longs at $9A0E..., the list of lists at $A53E, $FFFF
// ends); its height bounces on a 76-word table ($9976). $97A2 clears the lines
// it left since two frames ago (the same buffer).
// --------------------------------------------------------------------------
const st = @import("st.zig");
const T = @import("tcb2.zig");

const Ram = st.Ram;

const RING_POS: u32 = 0xA53A; // .l byte offset, 0..$C0 stepping 8
const SCRIPT: u32 = 0xA6FE; // .l -> the next position
const LISTS: u32 = 0xA702; // .l -> the next list
const LISTS_START: u32 = 0xA53E;
const SHIFT_OFFSET: u32 = 0x9700; // .l x 16: preshift * $1644
const BOUNCE: u32 = 0x9976; // .w x 76: lines
const BOUNCE_POS: u32 = 0x9794; // .w
const OFFSET: u32 = 0x9790; // .l the logo's line offset + $17C0
const AT: u32 = 0x9796; // .l its address this frame, then the two before
const CLEAR_DELAY: u32 = 0x9946; // .w

pub fn step(r: *const Ram) void {
    feed(r);
    height(r);
    draw(r);
    clearVacated(r);
}

/// $9638: the next position into the ring (and its copy 24 entries on).
fn feed(r: *const Ram) void {
    var pos = r.l(RING_POS) + 8;
    if (pos >= 0xC8) pos = 0;
    r.sl(RING_POS, pos);
    var a1 = r.l(SCRIPT);
    var x = r.l(a1);
    a1 += 4;
    if (x & 0x8000 != 0) {
        var a2 = r.l(LISTS);
        a1 = r.l(a2);
        a2 += 4;
        if (a1 == 0xFFFF_FFFF) {
            a2 = LISTS_START;
            a1 = r.l(a2);
            a2 += 4;
        }
        r.sl(LISTS, a2);
        x = r.l(a1);
        a1 += 4;
    }
    x +%= 0x10;
    const shift = r.l(SHIFT_OFFSET + ((x & 0xF) << 2));
    const d4: u32 = ((x >> 1) & 0xFFFF_FFF8) -% 0xA0;
    const d1: i32 = @as(i32, @intCast(((x >> 4) & 0xFFFF) * 6)) - 0x78;
    var src = T.ANCOOL + shift + 0x7E;
    var off: u32 = 0;
    if (d1 < 0) {
        src -%= @bitCast(d1);
    } else if (d1 > 6) {
        off = 8;
        src -%= @as(u32, @intCast(d1 - 6));
    } else {
        off = d4;
    }
    const a0 = T.ANCOOL_RING + pos;
    r.sl(a0 + 0xC0, src);
    r.sl(a0 + 0xC4, off);
    r.sl(a0 -% 8, src);
    r.sl(a0 -% 4, off);
    r.sl(SCRIPT, a1);
}

/// $9740.
fn height(r: *const Ram) void {
    var n = r.w(BOUNCE_POS) + 1;
    if (n >= 0x4C) n = 0;
    r.sw(BOUNCE_POS, n);
    const line = r.w(BOUNCE + 2 * @as(u32, n));
    const off = r.l(st.add(T.LINE160, st.sx(line << 2))) +% 0x17C0;
    r.sl(OFFSET, off);
    r.sl(AT + 8, r.l(AT + 4));
    r.sl(AT + 4, r.l(AT));
    r.sl(AT, off +% r.l(T.DRAWN));
}

/// $9576: 25 lines of 19 groups, planes 1-3.
fn draw(r: *const Ram) void {
    var ring = T.ANCOOL_RING + r.l(RING_POS);
    var line = r.l(T.DRAWN) +% r.l(OFFSET) +% 2;
    for (0..25) |k| {
        var src = r.l(ring) +% 0xE4 * @as(u32, @intCast(k));
        const dst = line +% r.l(ring + 4);
        ring += 8;
        for (0..19) |g| {
            r.cp(dst + 8 * @as(u32, @intCast(g)), src, 6);
            src += 6;
        }
        line +%= 0xA0;
    }
}

/// $97A2: planes 1-3 of the lines between the logo two frames ago and now.
fn clearVacated(r: *const Ram) void {
    const n = r.w(CLEAR_DELAY) -% 1;
    r.sw(CLEAR_DELAY, n);
    if (n & 0x8000 == 0) return;
    r.sw(CLEAR_DELAY, 0);
    var old: i32 = @bitCast(r.l(AT + 8));
    var now: i32 = @bitCast(r.l(AT));
    if (old == now) return;
    if (old > now) {
        var a: i32 = old + 0xFA0;
        while (true) {
            a -= 0xA0;
            clearLine(r, @bitCast(a));
            old -= 0xA0;
            if (!(old > now)) break;
        }
    } else {
        var a: i32 = now;
        while (true) {
            a -= 0xA0;
            clearLine(r, @bitCast(a));
            now -= 0xA0;
            if (!(now > old)) break;
        }
    }
}

fn clearLine(r: *const Ram, a: u32) void {
    for (0..20) |g| r.zero(a + 8 * @as(u32, @intCast(g)) + 2, 6);
}
