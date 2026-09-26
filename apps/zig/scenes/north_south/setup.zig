// --------------------------------------------------------------------------
// The state the map hands to do_battle (the reference RAM dump's battle
// variables, with the call's arguments replaced), then the battle's own setup:
// $AAD0 before the loop, $E3D0's prologue, the field $DC56, the armies $D8F4
// and the two sides $E0D8.
// --------------------------------------------------------------------------
const mem = @import("mem.zig");
const ad = @import("addr.zig");
const A = @import("assets.zig");
const gfx = @import("gfx.zig");
const u = @import("units.zig");
const G = @import("game.zig");
const Game = G.Game;

const B = mem.B;
const obj = ad.obj;

/// do_battle's arguments in the reference dump: armyA (the attacker) is the
/// Confederate record, armyB (the defender) the Union's.
const ARMY_A: u32 = ad.REC_CONFED + B;
const ARMY_B: u32 = ad.REC_UNION + B;

pub const Mode = enum(u8) { two_players = 0, confed_human = 1, union_human = 2, demo = 3 };

pub const Options = struct {
    field: u8, // 0 river, 1 canyon, 2 plain
    union_army: ?[3]u8, // infantry, cavalry, cannons; null keeps the dump's
    confed_army: ?[3]u8,
    mode: Mode,
    level_a: i32, // Union AI level ($1714A), 0..2
    level_b: i32, // Confederate AI level ($17158)
    seed: ?u32, // the RNG ($1C7FA); null keeps the dump's
};

pub fn start(g: *Game, o: Options) void {
    @memcpy(&g.m.ram, A.entry);
    const m = &g.m;
    if (o.union_army) |army| {
        m.setb(ad.REC_UNION, 1);
        for (army, 1..) |n, i| m.setb(ad.REC_UNION + @as(u32, @intCast(i)), n);
    }
    if (o.confed_army) |army| {
        m.setb(ad.REC_CONFED, 2);
        for (army, 1..) |n, i| m.setb(ad.REC_CONFED + @as(u32, @intCast(i)), n);
    }
    if (o.seed) |s| m.setl(ad.RNG, s);
    g.cfg = .{ .mode = @intFromEnum(o.mode), .level_a = o.level_a, .level_b = o.level_b, .retreat_ok = true, .army_a = ARMY_A, .army_b = ARMY_B };
    g.field = o.field;
    g.pen = 0;
    g.result = 0;
    g.frames = 0;
    g.nevents = 0;
    g.cost.reset();
    g.pace.reset();
    for (0..16) |i| g.palette[i] = A.fieldPalette(o.field, i);
    @memset(&gfx.screens[0], 0);
    @memset(&gfx.screens[1], 0);
    gfx.planarToIndices(A.fieldPicture(o.field), &gfx.screens[2]);
    for (&g.orient, 0..) |*bank, bi| {
        for (bank, 0..) |*f, n| f.* = if (A.banks[bi].get(n)) |s| s.flipped else false;
    }
    setup(g, o.field);
}

fn setup(g: *Game, field: i32) void {
    const m = &g.m;
    g.pen = 0;
    // $AAD0 before the battle proper: the cached picture (+2 = its palette),
    // the fade step and two display parameters
    m.setl(0x1CC90, m.l(0x1CCF0 + 4 * @as(u32, @intCast(field))) +% 2);
    m.setw(0x1C90E, 0x40);
    m.setw(0x1C912, 4);
    m.setw(0x1C910, 0x0E);
    m.setw(ad.FIELD, field);
    m.setw(ad.SIDE_B + ad.S_CPU, 0);
    m.setw(ad.SIDE_A + ad.S_CPU, 0);
    for ([_]u32{ ad.SIDE_A, ad.SIDE_B }) |s| {
        for ([_]u32{ ad.S_CANLEAD, ad.S_CAVLEAD, ad.S_INFLEAD }) |f| m.setw(s + f, -1);
    }
    // switch A, switch B, retreat A, retreat B: LShift/RShift, Esc/Backspace
    g.keys = if (m.b(ad.CFG_JOYPLAYER) == 1) .{ 0x2A, 0x36, 0x01, 0x0E } else .{ 0x36, 0x2A, 0x0E, 0x01 };
    if (g.cfg.mode != 0) g.keys = .{ 0x36, 0x36, 0x0E, 0x0E };
    if (g.cfg.mode & 1 != 0) m.setw(ad.SIDE_A + ad.S_CPU, 1);
    if (g.cfg.mode & 2 != 0) m.setw(ad.SIDE_B + ad.S_CPU, 1);
    fieldSetup(g);
    m.setw(ad.SIDE_A + ad.S_LEVEL, g.cfg.level_a);
    m.setw(ad.SIDE_B + ad.S_LEVEL, g.cfg.level_b);
    if (m.b(g.cfg.army_a -% B) == 1) {
        m.setl(ad.REC_A, g.cfg.army_a);
        m.setl(ad.REC_B, g.cfg.army_b);
    } else {
        m.setl(ad.REC_A, g.cfg.army_b);
        m.setl(ad.REC_B, g.cfg.army_a);
    }
    m.setw(ad.FRAME_PARITY, 0);
    spawnArmies(g);
    sideInit(g, ad.SIDE_A, 3);
    sideInit(g, ad.SIDE_B, 0x12C);
    m.setw(ad.DEMO_TIMER, 0x7D0);
}

// fieldSetup walks ns.app's terrain tables and decor lists, whose cell lists
// end at $FF: prove on the ROM bytes that every walk stays inside the ROM
// and every cell inside the 40x50 grid, so no data-driven loop can run away.
comptime {
    @setEvalBranchQuota(20000);
    for (ad.T_TERRAIN) |t| if (t[0] + 50 * 13 > mem.ROM_HI or t[1] + 13 > 40) @compileError("terrain table out of range");
    const lists = ad.DECOR_RIVER ++ [_]ad.Decor{ad.DECOR_CANYON} ++ ad.DECOR_PLAIN;
    for (lists) |d| {
        const n: u32 = @intCast(d.end - 0x18);
        if (d.list + 6 * n > mem.ROM_HI) @compileError("decor list out of range");
        var c = d.cells - mem.ROM_LO;
        for (0..n) |_| {
            while (A.rom[c] != 0xFF) : (c += 2) {
                const cell = @as(i32, @as(i8, @bitCast(A.rom[c]))) * 50 + @as(i8, @bitCast(A.rom[c + 1]));
                if (cell < 0 or cell >= 2000) @compileError("decor cell outside the grid");
            }
            c += 1;
        }
    }
}

fn fieldSetup(g: *Game) void { // $DC56
    const m = &g.m;
    const fld = m.w(ad.FIELD);
    var i: u32 = 0;
    while (i < 2000) : (i += 1) m.setb(ad.GRID + i, 0);
    m.setw(ad.BRIDGE_Y, if (fld == 0) 0x49 else if (fld == 1) 0x4E else 0);
    if (fld != 2) {
        const t = ad.T_TERRAIN[@intCast(fld)];
        var tbl = t[0];
        m.setw(ad.BRIDGE_HITS, 0);
        g.blit(.bg, .decor, 0x14, 0x90, fld * 5 + 0x5A);
        var row: u32 = 0;
        while (row < 50) : (row += 1) {
            var col = t[1];
            while (col < t[1] + 13) : (col += 1) {
                var v = mem.romB(tbl);
                if (v >= 1 and v <= 3) v += 0x63; // 1 water $64, 2 bridge deck $65, 3 ford $66
                m.setb(ad.GRID + col * 50 + row, v);
                tbl += 1;
            }
        }
    }
    const d = if (fld == 1) ad.DECOR_CANYON else if (fld == 0) ad.DECOR_RIVER[g.rnd(2)] else ad.DECOR_PLAIN[g.rnd(2)];
    m.setw(ad.DECOR_END, d.end);
    m.setb(ad.DRAW, 0x21);
    m.setw(obj(33) + 2, 0xDC);
    u.spawn(g, 0, 0x21, 0, 0, 0, ad.T_DECOR_SENTINEL + B, false); // every slot: state 0
    var lst = d.list;
    var cells = d.cells;
    var k: i32 = 0x18;
    while (k < d.end) : (k += 1) {
        const o = obj(k);
        m.setw(o, mem.romW(lst));
        m.setw(o + 2, mem.romW(lst + 2));
        m.setw(o + 4, mem.romW(lst + 4));
        m.setw(o + 6, mem.romW(lst + 4));
        lst += 6;
        u.drawInsert(g, m.w(o + 2), k);
        while (mem.romB(cells) != 0xFF) {
            const cell: u32 = @bitCast(@as(i32, ad.GRID) + mem.romSb(cells) * 50 + mem.romSb(cells + 1));
            cells += 2;
            m.setb(cell, k);
            if (m.w(o + 4) == 0x15) { // the bridge rail: the crossing
                m.setb(cell, 0x28);
                m.setw(ad.RAIL_OBJ, k);
            }
        }
        cells += 1;
    }
    g.pen = 0;
    m.setw(ad.UNUSED_26, 0);
    m.setw(ad.CF40, 1);
    m.setw(ad.CF42, 1);
}

fn spawnArmies(g: *Game) void { // $D8F4
    const m = &g.m;
    const Side = struct { s: u32, rec: u32, lanes: u32, x: i32, can: u32, first: i32 };
    const sides = [2]Side{
        .{ .s = ad.SIDE_A, .rec = ad.REC_A, .lanes = ad.T_LANES_A, .x = -30, .can = ad.T_CAN_A, .first = 0 },
        .{ .s = ad.SIDE_B, .rec = ad.REC_B, .lanes = ad.T_LANES_B, .x = 0x14A, .can = ad.T_CAN_B, .first = 12 },
    };
    for (sides, 0..) |sd, i| {
        const line = if (i == 0) ad.T_LINE_A else ad.T_LINE_B;
        var p = sd.lanes + g.rnd(3) * 2;
        const rec = m.l(sd.rec) -% B;
        var alive: i32 = 0;
        if (m.b(rec + 3) != 0) {
            u.spawn(g, sd.first, m.b(rec + 3), 0x1B, sd.x, mem.romW(p), sd.can + B, false);
            p += 2;
            m.setw(sd.s + ad.S_CANLEAD, sd.first);
            alive = 4;
        }
        if (m.b(rec + 2) != 0) {
            u.spawn(g, sd.first + 3, @min(m.b(rec + 2), 3), 0x0A, sd.x, mem.romW(p), line + B, false);
            p += 2;
            m.setw(sd.s + ad.S_CAVLEAD, sd.first + 3);
            alive += 2;
        }
        if (m.b(rec + 1) != 0) {
            u.spawn(g, sd.first + 6, @min(m.b(rec + 1), 6), 3, sd.x, mem.romW(p), line + B, false);
            m.setw(sd.s + ad.S_INFLEAD, sd.first + 6);
            alive += 1;
        }
        m.setw(sd.s + ad.S_ALIVE, alive);
    }
}

fn sideInit(g: *Game, s: u32, hudx: i32) void { // $E0D8
    const m = &g.m;
    m.setw(s + ad.S_HUDX, hudx);
    if (m.w(s + ad.S_CPU) == 0) {
        const a = m.w(s + ad.S_ALIVE);
        const sel: [2]i32 = if (a & 4 != 0) .{ 4, 0x18 } else if (a & 2 != 0) .{ 2, 0x1A } else .{ 1, 0x19 };
        m.setw(s + ad.S_SEL, sel[0]);
        g.blit(.bg, .decor, sel[1], hudx, 0x13);
    }
    for ([_]u32{ ad.S_SWITCH, ad.S_BLAST, ad.S_DIST, ad.S_SABRE, ad.S_VOLLEY, ad.S_INFREF, ad.S_CAVREF }) |f| m.setw(s + f, 0);
    for ([_]u32{ ad.S_POWER, ad.S_CAVACT, ad.S_INFACT, ad.S_CANACT }) |f| m.setw(s + f, 8);
    m.setw(s + ad.S_AMMO, 9);
    m.setw(s + ad.S_20, 0);
    m.setw(s + ad.S_CAVHALT, 2);
    m.setw(s + ad.S_ENTER, m.w(s + ad.S_ALIVE));
    m.setw(s + ad.S_RETREAT, 0);
    m.setl(s + ad.S_CAVFORM, ad.T_LINE_A + B);
    m.setl(s + ad.S_INFFORM, ad.T_LINE_A + B);
    m.setl(s + ad.S_BLASTANIM, ad.A_BLAST + B);
    for ([_]u32{ ad.S_AI_CAN, ad.S_AI_CAV, ad.S_AI_INF }) |f| m.setw(s + f, 1);
}
