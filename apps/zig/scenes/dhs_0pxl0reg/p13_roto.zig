// --------------------------------------------------------------------------
// P13's rotozoom ($1C710), transcribed with its 68000 register tricks: the
// 16.16 steps are swapped and byte-rotated so one addx carries between the
// halves, and a texel address is (row start + column displacement) & $3FFF,
// 4 bytes a texel (each pixel of the 64x64 texture stored doubled).
// All of it is 32-bit wrapping integer math, exactly as the model has it.
// --------------------------------------------------------------------------
const core = @import("core.zig");
const assets = @import("assets.zig");

fn sn(o: u32) i64 {
    return core.sine[(o & 0x7FF) >> 1];
}
fn cs(o: u32) i64 {
    return core.sine[((o & 0x7FF) >> 1) + 256];
}
fn lo(v: i64) u32 {
    return @truncate(@as(u64, @bitCast(v)));
}
fn swapw(v: u32) u32 {
    return (v << 16) | (v >> 16);
}

/// Fill cells 17..52 of the 25 rows with texel register numbers for time t.
pub fn render(t: u32, rows: *[25][54]u8) void {
    var a = (t *% 2) & 0x7FF;
    const s1 = sn(a);
    const c1 = cs(a);
    a = (a + 0x100) & 0x7FF;
    const s2 = sn(a);
    const c2 = cs(a);
    a = (a + 0x200) & 0x7FF;
    const s3 = sn(a);
    const c3 = cs(a);
    const z = (s3 >> 4) + 0x800;
    const e1 = s1 * z;
    const e2 = c1 * z;
    const sv1 = lo(e1 + s3 * 1000);
    const sv2 = lo(e2 + c3 * 100);
    const d3 = lo((s2 * z - e1) >> 6);
    const sv4 = lo((c2 * z - e2) >> 6);
    const e5 = lo((s3 * z - e1) >> 6);
    const e6 = lo((c3 * z - e2) >> 6);

    // column displacements: swapped / rotated halves, one addx per step
    var d1 = swapw(sv1);
    const d5r = swapw(e5);
    var d2 = (sv2 >> 8) | (sv2 << 24);
    const d6r = (e6 >> 8) | (e6 << 24);
    const x1 = d1 & 0xFFFF;
    d1 = (d1 & 0xFFFF0000) | (d2 & 0xFFFF);
    d2 = (d2 & 0xFFFF0000) | x1;
    const d5 = (d5r & 0xFFFF0000) | (d6r & 0xFFFF);
    const d6 = (d6r & 0xFFFF0000) | (d5r & 0xFFFF);
    var disp: [36]u32 = undefined;
    for (&disp) |*dp| {
        const r = @as(u64, d1) + d5;
        const x: u32 = @intFromBool(r > 0xFFFFFFFF);
        d1 = @truncate(r);
        d2 = d2 +% d6 +% x;
        const v = (((d1 & 0xFFFF) >> 2) & 0xFF00) | (d2 & 0xFF);
        dp.* = v & 0x3FFC;
    }

    // row starts
    var r1 = sv1;
    var r2 = sv2 << 6;
    var d4 = sv4 << 6;
    var a6 = d3;
    var d0: u32 = 0;
    var a4: u32 = 0;
    const a2: u32 = 0;
    const a5: u32 = 0x186A0;
    for (rows) |*row| {
        a6 +%= d0;
        d0 +%= a2;
        d4 +%= a4;
        a4 +%= a5;
        r1 +%= a6;
        r2 +%= d4;
        const start = ((swapw(r2) & 0xFF00) | (swapw(r1) & 0xFF)) & 0x3FFC;
        for (disp, 0..) |dp, j| row[17 + j] = assets.p13_tex[((start + dp) & 0x3FFF) >> 2];
    }
}
