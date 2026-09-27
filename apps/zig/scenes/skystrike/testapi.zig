// --------------------------------------------------------------------------
// The headless harness's door (apps/skystrike_headless.mjs), exported by
// skystrike.zig in this cart only.
//
//   reset(seed)       power on in lockstep, RND seeded
//   vbl(n)            n VBLs; returns the flow label (flow.L)
//   key(cp, down)     a host key; stick(bits) the arrows (1 2 4 8) + fire $80
//   val(what)         0 label, 1 flow faults, 2 PEEK/POKE outside, 3 bad
//                     indexes, 4 refused zones, 5 refused zg.mem, 6 sound
//                     commands, 7 divisions by zero, 8 VBLs, 9 TIMER,
//                     10 main-loop passes, 11 SP# x 1000, 20+ a variable
//                     (VARS), 100+i sound command i (op << 8 | arg),
//                     200 + 2k + e enemy e's ENEMY[k]
//   poke(what, v)     11 SP# x 1000, 12 clear the sound log, 20+ a variable,
//                     200+ an enemy's (as val); in both val and poke,
//                     0x50000+ is a PEEK / POKE address (bank << 16 | offset),
//                     e.g. SC9 + sx, a screen's type (tools/skystrike/
//                     render_tileset.mjs draws every type this way)
//   refuse()          one zg.mem allocation too big to grant (--break alloc)
//   ptr(what)         0 physic, 1 back, 2 bank 5, 3 bank 6 (320x200
//                     indices), 4 the colour registers (16 u16)
// --------------------------------------------------------------------------
const zg = @import("zigos");
const machine = @import("machine.zig");
const input = @import("input.zig");
const rnd = @import("rnd.zig");
const scr = @import("scr.zig");
const pal = @import("pal.zig");
const zone = @import("zone.zig");
const sound = @import("sound.zig");
const B = @import("basic.zig");
const flow = @import("flow.zig");
const S = @import("stos.zig");
const zt = @import("zig_testapi.zig");
const V = @import("vars.zig");
const v = &V.v;

pub var lockstep: bool = false;

const VARS = [_][]const u8{
    "x",     "y",   "sx",   "al",    "th",    "r",       "scre", "kls",
    "planes", "fuel", "crsh", "ld",  "bale",  "fre",     "mission", "lvl",
    "ammo",  "z2",  "en",   "cl",    "uc",    "dif",     "ti",   "nf",
    "mfin",  "tgtx", "fust", "atlf", "bf",    "rkf",     "bnf",  "esx",
    "r2",    "scre",
};

pub fn reset(seed: u32) callconv(.c) void {
    lockstep = true;
    machine.reset();
    rnd.seed = seed;
    @import("zig_mode.zig").set(false); // the ST's screens and traces
}

pub fn vbl(n: u32) callconv(.c) u32 {
    var i: u32 = 0;
    while (i < n) : (i += 1) machine.vbl();
    return @intFromEnum(flow.pc);
}

pub fn key(cp: u32, down: u32) callconv(.c) void {
    if (down != 0) @import("../skystrike.zig").hostKey(cp) else @import("../skystrike.zig").hostKeyUp(cp);
}

pub fn stick(bits: u32) callconv(.c) void {
    input.stick = @intCast(bits & 15);
    input.fire_down = bits & 0x80 != 0;
}

const ENEMY = [_][]const u8{ "esx_a", "eal_a", "ex_a", "ey_a", "fre_a", "er_a" };

fn enemyPtr(i: usize) ?*i32 {
    inline for (ENEMY, 0..) |name, k| {
        if (i / 2 == k) return &@field(v.*, name)[i % 2];
    }
    return null;
}

fn varPtr(i: usize) ?*i32 {
    inline for (VARS, 0..) |name, k| {
        if (i == k) return &@field(v.*, name);
    }
    return null;
}

pub fn val(what: u32) callconv(.c) i32 {
    return switch (what) {
        0 => @intFromEnum(flow.pc),
        1 => @intCast(flow.faults),
        2 => @intCast(scr.oob),
        3 => @intCast(B.bad_index),
        4 => @intCast(zone.refused),
        5 => @intCast(zg.mem.failures()),
        6 => @intCast(sound.log_total),
        7 => @intCast(B.div_zero),
        8 => @truncate(@as(i64, @intCast(machine.vbls))),
        9 => S.timer,
        10 => @intCast(@import("pass.zig").passes),
        11 => B.ftoi(v.sp_f * 1000.0),
        else => other(what),
    };
}

/// PEEK / POKE addresses as the BASIC computes them (START(5) = 5 << 16).
const BANK_ADDR: u32 = 0x50000;

fn other(what: u32) i32 {
    if (what >= BANK_ADDR) return scr.peek(@intCast(what));
    if (what >= zt.BASE and what < zt.BASE + 100) return zt.val(what - zt.BASE);
    if (what >= 200) {
        if (enemyPtr(what - 200)) |p| return p.*;
        return 0;
    }
    if (what >= 100) {
        const i = what - 100;
        return if (i < sound.log_n) sound.log[i] else -1;
    }
    if (what >= 20 and what < 20 + VARS.len) {
        if (varPtr(what - 20)) |p| return p.*;
    }
    return 0;
}

pub fn poke(what: u32, value: i32) callconv(.c) void {
    if (what == 11) {
        v.sp_f = @as(f64, @floatFromInt(value)) / 1000.0;
        return;
    }
    if (what >= 20 and what < 20 + VARS.len) {
        if (varPtr(what - 20)) |p| p.* = value;
    }
    if (what == 12) sound.log_n = 0;
    if (what == 13) sound.sent_n = 0;
    if (what >= BANK_ADDR) return scr.poke(@intCast(what), value);
    if (what >= zt.BASE and what < zt.BASE + 100) return zt.poke(what - zt.BASE, value);
    if (what >= 200) {
        if (enemyPtr(what - 200)) |p| p.* = value;
    }
}

pub fn refuse() callconv(.c) void {
    _ = zg.mem.alloc(u8, 64 << 20);
}

pub fn ptr(what: u32) callconv(.c) ?[*]u8 {
    return switch (what) {
        0 => scr.get(.physic).ptr,
        1 => scr.get(.back).ptr,
        2 => scr.get(.b5).ptr,
        3 => scr.get(.b6).ptr,
        4 => @ptrCast(&pal.hw),
        else => zt.ptr(what),
    };
}
