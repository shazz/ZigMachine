// --------------------------------------------------------------------------
// P3 sine ribbon scroller, 12 px true-colour cells. Kernel $1AD86: K+1 line
// pairs, each line 38 x move.w (An)+,(Am) from a 100-word buffer row (a
// 50-column circular strip stored twice) at window S. Line A of a pair starts
// at rel 308+1024p, line B at 816+1024p: 4 px further left, from where the
// loop's nops sit. Each frame ($1B88C) clears one column and draws 16 bars of
// 16 colours at sine heights into it; the window then moves one column.
// --------------------------------------------------------------------------
const core = @import("core.zig");
const out = @import("out.zig");
const rip = @import("rip.zig");

var S: u32 = 0; // $3DFAE, bytes 0..$62
var P: u32 = 0; // $1BA12
var speed: u32 = 0; // $1BA14
var K: u32 = 0; // $1AF32
var c1af26: u32 = 0;
var from_tabs = false; // the colours come from the rainbow, later the fade tables
var srcofs: u32 = 0; // $3DFAA
var c1ad0e: u32 = 0;
var c1ad70: u16 = 0;
var buf: [233][100]u16 = undefined;
var rainbow: [512]u16 = undefined; // $1BA66: $1BA84 x 32 at $A3D96
var tabs: [24][512]u16 = undefined; // $1BA2A: fade from black towards $3DFB4

pub fn reset() void {
    S = rip.P3_S;
    P = rip.P3_P;
    speed = rip.P3_SPEED;
    K = rip.P3_K;
    c1af26 = rip.P3_C1AF26;
    from_tabs = false;
    srcofs = rip.P3_SRCOFS;
    c1ad0e = rip.P3_C1AD0E;
    c1ad70 = rip.P3_C1AD70;
    for (&buf) |*r| @memset(r, 0);
}

/// $1ACC6: the colour tables, then 61 columns drawn so the ribbon is full.
pub fn init() void {
    for (0..32) |k| @memcpy(rainbow[16 * k ..][0..16], &rip.P3_RAINBOW);
    @memset(&tabs[0], 0);
    for (1..24) |k| {
        tabs[k] = tabs[k - 1];
        core.step1(&tabs[k], &rip.P3_TGT);
    }
    for (0..61) |_| {
        draw();
        scroll();
    }
}

/// $1AF34: row offset of bar `idx` (a 4096-entry table of sin * 199, step 6).
fn barY(idx: u32) u32 {
    const d2 = (6 * idx) & 0x7FF;
    return @intCast(100 + core.sinMul(d2 >> 1, 199));
}

fn draw() void {
    const c = S >> 1;
    for (&buf) |*r| {
        r[c] = 0;
        r[c + 50] = 0;
    }
    const col: *const [512]u16 = if (from_tabs) &tabs[srcofs / 0x400] else &rainbow;
    var n: usize = 0;
    var idx = P >> 2;
    for (0..16) |_| {
        const y = barY(idx);
        idx += 15;
        for (0..16) |i| {
            const v = col[n];
            n += 1;
            for ([_]u32{ y + 2 * @as(u32, @intCast(i)), y + 2 * @as(u32, @intCast(i)) + 1 }) |rr| {
                buf[rr][c] = v;
                buf[rr][c + 50] = v;
            }
        }
    }
    P = (P + speed) & 0x1FFF;
}

fn scroll() void {
    S = if (S >= 0x62) 0 else S + 2;
}

fn frame() void {
    core.colour = 0;
    draw();
    scroll();
}

pub fn v1ad1a() void {
    speed = 8;
    frame();
}

pub fn v1ad24() void {
    speed = 0xC;
    frame();
}

pub fn v1ad10() void {
    speed = 4;
    frame();
}

/// $1ACEE: every 6 frames the ribbon one fade table darker.
pub fn v1acee() void {
    frame();
    c1ad0e -= 1;
    if (c1ad0e == 0) {
        c1ad0e = 6;
        if (srcofs != 0) srcofs -= 0x400;
    }
}

/// $1AD42: white flash, and from now on the colours come from the fade tables.
pub fn v1ad42() void {
    core.colour = 0x777;
    from_tabs = true;
    srcofs = 0x5C00;
}

pub fn m1ad5e() void {
    speed = 0xC;
    c1ad70 -%= 1;
    if (c1ad70 == 0) {
        for (0..61) |_| {
            draw();
            scroll();
        }
    }
}

pub fn kernel(l0: u32) void {
    const c0 = S >> 1;
    for (0..K + 1) |p| {
        const pair: u32 = 1024 * @as(u32, @intCast(p));
        for ([_]u32{ 308, 816 }, 0..) |base, half| {
            const row = &buf[2 * p + half];
            for (0..38) |j| out.emit(l0, base + pair + 12 * @as(u32, @intCast(j)), row[c0 + j]);
        }
    }
    out.emit(l0, 308 + 1024 * (K + 1), 0);
    core.colour = 0;
    c1af26 -= 1;
    if (c1af26 == 0) {
        c1af26 = 0x32;
        K = if (K >= 0x64) 0x73 else K + 0xF;
    }
}
