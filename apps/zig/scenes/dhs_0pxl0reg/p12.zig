// --------------------------------------------------------------------------
// P12 fire with stamped text. Kernel $11972 (Timer A 255/50): 36 rows x 4
// lines of 48 x 8 px cells, then 0 (a6); line l of row r starts at rel
// 348+2048r+(0,516,1024,1540)[l]: the 508/516-cycle lines put lines 1 and 3
// 4 px right. Registers d0..a5 = 14 palette words; heat >> 2 picks one.
// Per frame ($1189C) into the back buffer: stamp the text bitmap, feed two
// seed rows, cool (average of 4 neighbours >> 2), render. The update misses
// about every other frame from the CPU overload; that cadence is replayed
// from the measured call schedule, as the original ran.
// --------------------------------------------------------------------------
const core = @import("core.zig");
const out = @import("out.zig");
const rip = @import("rip.zig");
const assets = @import("assets.zig");

const HEAT0 = 0xF0; // heat row 0 in H
var hv: u32 = 0; // the stamped heat value
var c_hv: i32 = 0;
var n: u32 = 0; // stamped rows - 1
var r0: u32 = 0; // byte offset of the first stamped row
var c_n: i32 = 0;
var tofs: u32 = 0;
var sofs: u32 = 0;
var pal: [14]u16 = undefined;
var c1192a: u32 = 0;
var c11952: u32 = 0;
var H: [0x8A0 + 256]u8 = undefined;
var bufs: [2][36][48]u8 = undefined;
var front: usize = 1;

pub fn reset() void {
    hv = rip.P12_HV;
    c_hv = rip.P12_C_HV;
    n = rip.P12_N;
    r0 = rip.P12_R0;
    c_n = rip.P12_C_N;
    tofs = rip.P12_TOFS;
    sofs = rip.P12_SOFS;
    pal = rip.P12_PAL;
    c1192a = rip.P12_C1192A;
    c11952 = rip.P12_C11952;
}

pub fn init() void {
    core.colour = 0;
    @memcpy(&H, assets.p12_heat0);
    render(&bufs[0]);
    render(&bufs[1]);
    front = 1;
}

fn render(dst: *[36][48]u8) void {
    for (dst, 0..) |*row, r| {
        for (row, 0..) |*c, col| c.* = rip.P12_OPC[H[HEAT0 + r * 48 + col]];
    }
}

pub fn vblIn() void {
    core.colour = 0;
    c1192a -= 1;
    if (c1192a == 0) {
        c1192a = 3;
        core.step1(&pal, &rip.P12_TGT_22CC0);
    }
}

pub fn vbl() void {
    core.colour = 0;
}

pub fn vblOut() void {
    core.colour = 0;
    c11952 -= 1;
    if (c11952 == 0) {
        c11952 = 3;
        core.step1(&pal, &rip.P12_TGT_22CA4);
    }
}

/// $12830: the text bitmap rows (48 bits each) set H = hv where a bit is 1.
fn stamp() void {
    var a: usize = HEAT0 + r0;
    var t: usize = tofs + 0x2A;
    for (0..n + 1) |_| {
        const row = assets.p12_txt[t..][0..6];
        t += 6;
        for (0..48) |c| {
            if (row[c >> 3] & (@as(u8, 0x80) >> @intCast(c & 7)) != 0) H[a + c] = @truncate(hv);
        }
        a += 48;
    }
    c_n -= 1;
    if (c_n <= 0) {
        c_n = 3;
        if (n != 0x27) {
            n += 1;
            r0 -= 0x30;
        }
    }
    if (tofs >= 0xC474) {
        tofs = 0;
    } else {
        tofs += 0x18C;
        c_hv -= 1;
        if (c_hv == 0 and hv != 0x3F) {
            hv += 1;
            c_hv = 2;
        }
    }
}

pub fn step() void {
    front = 1 - front;
    stamp();
    @memcpy(H[0x810..][0..96], assets.p12_seed[sofs..][0..96]); // $12DB6: rows 38..39
    sofs = if (sofs == 0x300) 0 else sofs + 0x30;
    for (0..40) |r| { // $12AFC, rows in memory order
        for (0..48) |c| {
            const o = HEAT0 + r * 48 + c;
            const sum: u32 = @as(u32, H[o]) + H[o - 48] + H[o + 48] + H[o + 96];
            H[o - 48] = @intCast((sum & 0xFF) >> 2);
        }
    }
    render(&bufs[1 - front]);
}

pub fn kernel(l0: u32) void {
    var S: u32 = 0;
    for (bufs[front], 0..) |cells, ri| {
        const r: u32 = @intCast(ri);
        for ([_]u32{ 0, 516, 1024, 1540 }) |off| {
            S = 348 + 2048 * r + off;
            for (cells, 0..) |c, j| out.emit(l0, S + 8 * @as(u32, @intCast(j)), pal[c]);
            out.emit(l0, S + 384, 0);
        }
    }
    out.emit(l0, S + 480, 0);
    core.colour = 0;
}
