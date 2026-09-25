// --------------------------------------------------------------------------
// P9 texture-mapped "glass", 12 px true-colour cells. Kernel $12F80 (Timer A
// 220/64): 66 rows x 2 lines of 33 cells, then 0; line 2r from rel 792+1024r,
// line 2r+1 from 1308+1024r: the 516/508-cycle pair puts the odd line 4 px
// right. The main hook renders into the back buffer; the buffers swap after
// the kernel, so frame F shows F-1's render.
//   cell = W[P/2 + img*128 + tex]
//     img: one of 5 33x66 images at fade level lev (IMG_n+1 = T[IMG_n], $181AC)
//     tex: TEX[u*66 + r], u from two sines ($9EDA6 / $A6DA6), stepped +4/-4
//     W  : 24 x 128 zeros, 48 fade tables (0 -> $26A42 -> $26B42), 24 x 128 $777
// --------------------------------------------------------------------------
const core = @import("core.zig");
const out = @import("out.zig");
const rip = @import("rip.zig");
const assets = @import("assets.zig");

var P: u32 = 0; // $25ABC, brightness offset into W (bytes)
var lev: u32 = 0; // $25AC0, $1104 a fade level
var img: usize = 0;
var A: i32 = 0; // $17FB4
var B: i32 = 0; // $17FB6
var a1: u32 = 0; // $17E5E (the init's own mapping pass)
var b1: u32 = 0;
var c12eb6: u16 = 0;
var c12ed2: u16 = 0;
var c1329a: u32 = 0;
var cimg: [5]u32 = undefined;
var done = false; // $12E28 patches itself after its first instruction
var tpow: [8][256]u8 = undefined; // T applied k times: the 8 fade levels
var W: [96 * 128]u16 = undefined;
var bufs: [2][66][33]u16 = undefined;
var back: usize = 0;
var front: usize = 1;
var ptr: [33]u32 = undefined;

pub fn reset() void {
    P = rip.P9_P;
    lev = rip.P9_LEV;
    img = 0;
    A = rip.P9_A;
    B = rip.P9_B;
    a1 = rip.P9_A1;
    b1 = rip.P9_B1;
    c12eb6 = rip.P9_C12EB6;
    c12ed2 = rip.P9_C12ED2;
    c1329a = rip.P9_C1329A;
    for (&cimg, rip.P9_CIMG) |*c, v| c.* = v;
    done = false;
}

/// $9EDA6: column offset from sin(i+1) * 700; $A6DA6 from sin(6(i+1)) * 300.
fn tx(i: u32) u32 {
    return x66(core.sinMul((i + 1) % 1024, 700));
}
fn ty(i: u32) u32 {
    return x66(core.sinMul((6 * (i + 1)) % 1024, 300));
}
fn x66(v: i32) u32 {
    return @as(u32, @intCast(@mod(512 + v, 126))) * 66;
}

pub fn init() void {
    core.colour = 0;
    if (done) return;
    done = true;
    for (0..256) |v| tpow[0][v] = @intCast(v);
    for (1..8) |k| {
        for (0..256) |v| tpow[k][v] = rip.P9_T[tpow[k - 1][v]];
    }
    @memset(W[0 .. 24 * 128], 0);
    var t = [_]u16{0} ** 128;
    @memcpy(W[24 * 128 ..][0..128], &t);
    var n: usize = 25;
    for ([_][]const u16{ &rip.P9_TGT_26A42, &rip.P9_TGT_26B42 }, [_]usize{ 23, 24 }) |tgt, steps| {
        for (0..steps) |_| {
            core.step1(&t, tgt);
            @memcpy(W[n * 128 ..][0..128], &t);
            n += 1;
        }
    }
    @memset(W[72 * 128 ..], 0x777);
    for (&bufs) |*bb| for (bb) |*r| @memset(r, 0);
    back = 0;
    front = 1;
    for (&ptr, 0..) |*p, c| p.* = tx(a1 / 4 + @as(u32, @intCast(c))) + tx(b1 / 4 + @as(u32, @intCast(c))); // $17D0C
    a1 += 4;
    b1 -= 4;
    levelStep();
    render();
    swap();
}

fn levelStep() void {
    c1329a -= 1;
    if (c1329a == 0) {
        c1329a = 6;
        if (lev < 0x771C) lev += 0x1104;
    }
}

/// $1329C
fn render() void {
    const pow = &tpow[lev / 0x1104];
    const pic = assets.p9_images[img * 2178 ..][0..2178];
    const base = P >> 1;
    for (0..33) |c| {
        const p = ptr[c];
        for (0..66) |r| {
            const texel = assets.p9_tex[(p + @as(u32, @intCast(r))) % assets.p9_tex.len];
            bufs[back][r][c] = W[base + @as(u32, pow[pic[c * 66 + r]]) * 128 + texel];
        }
    }
}

pub fn swap() void {
    const t = back;
    back = front;
    front = t;
}

/// $17E62
fn mapping() void {
    for (&ptr, 0..) |*p, c| {
        const cc: u32 = @intCast(c);
        p.* = tx(@as(u32, @intCast(A)) / 4 + cc) + ty(@as(u32, @intCast(B)) / 4 + cc);
    }
    A += 4;
    B -= 4;
    if (B < 0) {
        A = 0;
        B = 0x3FFC;
    }
}

/// $12EB8
fn step() void {
    mapping();
    c12ed2 -%= 1;
    if (c12ed2 & 0x8000 != 0) levelStep();
    render();
    core.later(.p9_swap, 0);
}

pub fn m12e8a() void {
    c12eb6 -%= 1;
    if (c12eb6 == 0) P = 0x4800;
    step();
    if (P != 0x2C00) P -= 0x100;
}

pub fn m12eb8() void {
    step();
}

pub fn m12e76() void {
    step();
    if (P != 0) P -= 0x100;
}

pub fn vbl() void {
    core.colour = 0;
}

/// $12EF4.. : show image k; its own counter resets the fade level once.
pub fn image(k: usize) void {
    cimg[k] -%= 1;
    if (cimg[k] == 0) lev = 0;
    img = k;
}

pub fn kernel(l0: u32) void {
    const buf = &bufs[front];
    for (0..66) |ri| {
        const r: u32 = @intCast(ri);
        for ([_]u32{ 792, 1308 }) |base| {
            const b = base + 1024 * r;
            for (0..33) |j| out.emit(l0, b + 12 * @as(u32, @intCast(j)), buf[ri][j]);
            out.emit(l0, b + 396, 0);
        }
    }
    out.emit(l0, 68384, 0);
    core.colour = 0;
}
