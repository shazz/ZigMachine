// --------------------------------------------------------------------------
// Lines 1-23 (the program's start: banks, DATA.DAT), 2220-2235 (the two
// graphics sheets), 2500-2611 (a new world) of the listing.
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const scr = @import("scr.zig");
const pac = @import("pac.zig");
const pal = @import("pal.zig");
const blocks = @import("blocks.zig");
const sprite = @import("sprite.zig");
const assets = @import("assets.zig");
const files = @import("files.zig");
const B = @import("basic.zig");
const flow = @import("flow.zig");
const V = @import("vars.zig");
const v = &V.v;

pub const steps = [_]flow.Entry{
    .{ .l = .boot, .f = lines1to23 },
};

/// 1: mode 0 : logic = physic : key off : click off : hide on : curs off :
///    sound init : samspeed auto : sambank 10 (the SNDH's first INIT)
/// 2: gosub 2220 : on error goto 2700   3: fade 1 : scbt = ...
fn lines1to23() flow.Act {
    scr.logic = .physic;
    sprite.mouse(false, 0, 0, 0);
    loadSheets();
    S.fadeBlack(1);
    v.scbt = 3 | 1 << 20 | 1 << 21 | 1 << 23 | 1 << 25 | 1 << 30 | @as(i32, @bitCast(@as(u32, 1) << 31));
    v.s7 = scr.start(7);
    v.so9 = v.s7;
    v.sno9 = scr.start(5) + 32033;
    v.sc9 = scr.start(6) + 32033;
    v.ghx9 = v.so9 + 105;
    v.lc9 = v.ghx9 + 51;
    readData();
    v.sx = 0;
    return .{ .go = .l2000 };
}

/// 2220: ink 0 : fade 1 : reserve as screen 5/6 : SKYPIC1 -> 5, SKYPIC2 -> 6,
/// each followed by bar 0,0 to 319,199 (physic, and back under AUTO BACK).
fn loadSheets() void {
    S.ink(0);
    S.fadeBlack(1);
    unpackTo(assets.SKYPIC1, .b5);
    S.bar(0, 0, 319, 199);
    unpackTo(assets.SKYPIC2, .b6);
    S.bar(0, 0, 319, 199);
}

/// 2230: logic = back : fade 1 : bload f$, back : unpack back, s :
/// screen copy s to back : logic = physic
pub fn unpackTo(file: []const u8, s: scr.Id) void {
    scr.logic = .back;
    S.fadeBlack(1);
    if (pac.unpack(file, s)) pal.hw = scr.pal[@intFromEnum(s)];
    blocks.copyAll(s, .back);
    scr.logic = .physic;
}

/// 8-22: DATA.DAT through INPUT #1 (the tr* and sct/mit tables are read
/// and never used).
fn readData() void {
    var r = files.data();
    for (0..13 * 6) |_| _ = r.int();
    v.wd_a = .{ 118, 112 };
    scr.poke(v.sc9, 1);
    for (0..16) |a| {
        v.dx_a[a] = r.int();
        v.dy_a[a][0] = r.int();
        v.dy_a[a][1] = v.dy_a[a][0];
    }
    v.dy_a[1][1] = 0;
    v.dy_a[7][1] = 0;
    for (&v.di_a) |*d| d.* = r.int();
    for (0..16) |a| {
        v.bm_s_a[a].set(r.field(false));
        v.bns_a[a] = 38 + @as(i32, @intCast(a));
    }
    v.bns_a[12] = 100;
    v.bns_a[13] = 108;
    v.bns_a[14] = 105;
    v.bns_a[15] = 107;
    for (0..13) |a| v.gt_a[a] = r.int();
    for (0..16) |a| {
        v.scrb_a[a] = r.int();
        v.fl_a[a] = r.int();
    }
    for (0..16) |_| _ = r.int();
    for (0..16) |a| {
        v.s_a[a][0] = @as(i32, @intCast(a)) + 1;
        v.s_a[a][1] = r.int();
    }
}

/// 2500-2599: a new world.
pub fn newWorld() void {
    scr.fillZero(scr.start(7), scr.start(7) + scr.BANK7_LEN);
    scr.fillZero(scr.start(5) + 32032, scr.start(5) + 32434);
    scr.fillZero(scr.start(6) + 32032, scr.start(6) + 32434);
    for (assets.SCRNDATA_DAT, 0..) |b, i| scr.poke(v.sc9 + @as(i32, @intCast(i)), b);
    v.clus = 0;
    v.alp = 0;
    v.cl = 0;
    v.ntr = 3;
    v.flf = 0;
    v.flgf = 0;
    v.bf = 0;
    v.bnf = 0;
    v.rkf = 0;
    v.rqf = 0;
    v.brdf = 0;
    v.junf = 0;
    newWorld2515();
}

fn newWorld2515() void {
    v.kls = 0;
    for (0..6) |a| {
        v.vs_a[a] = 0;
        v.vt_a[a] = 0;
        v.vsx_a[a] = 999;
    }
    v.rqsx = 0;
    v.btlsnk = 0;
    v.carsnk = 0;
    v.main = 0;
    for (0..6) |a| {
        if (scr.peek(v.sc9 + @as(i32, @intCast(a)) * 10) == 1) v.bse_a[a] = 1;
    }
    v.bse_a[0] = -1;
    v.bse_a[5] = -1;
    v.b_a[3] = 4;
    v.b_a[4] = 8;
    scr.poke(v.sc9 + 2, 8);
    var a: i32 = 2;
    while (a <= 50) : (a += 1) {
        if (scr.peek(v.sc9 + a) == 0 and S.rnd(100) > 30) scr.poke(v.sc9 + a, v.gt_a[B.ix(16, S.rnd(12))]);
    }
    v.b_a[8] = 0;
    v.bonus = 0;
    v.meb = 0;
    v.msb = 0;
    v.lvl = 999;
}

/// 2611: vehicle a becomes a truck.
pub fn truck(a: usize) void {
    v.vcp_a[a] = 0;
    v.vs_a[a] = 75;
    v.vt_a[a] = v.vs_a[a] * 2;
    v.vb_a[a] = 76;
    v.vh_a[a] = 2;
    v.vdx_a[a] = -8;
    v.vpt_a[a] = 1000;
    v.vw_a[a] = 1;
}
