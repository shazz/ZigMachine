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
//                     10+ a variable (VARS), 100+i sound command i
//   poke(what, v)     set variable 10+ (VARS)
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
const V = @import("vars.zig");
const v = &V.v;

pub var lockstep: bool = false;

const VARS = [_][]const u8{
    "x",     "y",   "sx",   "al",    "th",    "r",       "scre", "kls",
    "planes", "fuel", "crsh", "ld",  "bale",  "fre",     "mission", "lvl",
    "ammo",  "z2",  "en",   "cl",    "uc",    "dif",     "ti",   "nf",
    "mfin",  "tgtx", "fust", "atlf", "bf",    "rkf",     "bnf",  "esx",
};

pub fn reset(seed: u32) callconv(.c) void {
    lockstep = true;
    machine.reset();
    rnd.seed = seed;
}

pub fn vbl(n: u32) callconv(.c) u32 {
    var i: u32 = 0;
    while (i < n) : (i += 1) machine.vbl();
    return @intFromEnum(flow.pc);
}

pub fn key(cp: u32, down: u32) callconv(.c) void {
    if (down != 0) @import("../skystrike.zig").hostKey(cp) else if (cp == ' ') input.fire_down = false;
}

pub fn stick(bits: u32) callconv(.c) void {
    input.stick = @intCast(bits & 15);
    input.fire_down = bits & 0x80 != 0;
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
        11 => @intFromFloat(v.sp_f * 1000.0),
        else => other(what),
    };
}

fn other(what: u32) i32 {
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
}

pub fn ptr(what: u32) callconv(.c) ?[*]u8 {
    return switch (what) {
        0 => scr.get(.physic).ptr,
        1 => scr.get(.back).ptr,
        2 => scr.get(.b5).ptr,
        3 => scr.get(.b6).ptr,
        4 => @ptrCast(&pal.hw),
        else => null,
    };
}
