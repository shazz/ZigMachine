// --------------------------------------------------------------------------
// The game's sound commands -> skystrike.sndh (assets/screens/skystrike/
// sound.s), which runs STOS's music library, Maestro's digi player and the
// STOS PSG commands on the host's 68000.
//
// MUSIC n is a LOAD of subtune n (it restarts everything, as STOS's own
// MUSIC n silences the chip first). Every other command is a zg.sndhCall of
// $8000 + op << 8 + arg on the RUNNING image, so a sample or the engine note
// already sounding goes on; before the first load it loads subtune 4
// (silence) first. Each command is logged for the headless harness.
//
// ZIG mode sends none of this to the SNDH: it plays a MOD per situation
// (zig_music.zig, told by music / musicEnd which situation the game is at),
// its effects over it and the engine's PSG commands on the YM
// (zig_sound.zig). The log is the same in both modes.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const zm = @import("zig_music.zig");
pub const Situation = zm.Situation;

pub const NAME = "skystrike.sndh";
pub const RESIDENT: u16 = 0x8000;
pub const SILENCE: u8 = 4;

pub const Op = enum(u8) { music, samplay, samstop, samloop, volume, noise, envel, env_hi, env_lo, zplay, zstop };

pub var resident: bool = false;
/// The requests: op << 8 | arg, in the order the game made them.
pub var log: [64]u16 = undefined;
pub var log_n: usize = 0;
pub var log_total: u32 = 0;
/// What actually went to the SNDH (d0 & $7FFF), which in ZIG mode is not
/// the game's own command (zig_sound.zig), for the harness.
pub var sent: [64]u16 = undefined;
pub var sent_n: usize = 0;

fn record(op: Op, arg: u8) void {
    log_total += 1;
    if (log_n < log.len) {
        log[log_n] = @as(u16, @intFromEnum(op)) << 8 | arg;
        log_n += 1;
    }
}

fn call(op: Op, arg: u8) void {
    record(op, arg);
    if (@import("zig_sound.zig").cue != .effect) @import("zig_psg.zig").remember(op, arg);
    if (@import("zig_hooks.zig").zig) return @import("zig_sound.zig").route(op, arg);
    send(op, arg);
}

/// A command on the running image, as it is.
pub fn send(op: Op, arg: u8) void {
    const d0 = @as(u16, @intFromEnum(op)) << 8 | arg;
    if (sent_n < sent.len) {
        sent[sent_n] = d0;
        sent_n += 1;
    }
    if (!resident) {
        zg.requestSongTune(NAME, SILENCE);
        resident = true;
    }
    _ = zg.sndhCall(NAME, RESIDENT | d0);
}

/// MUSIC n at a switch point: `sit` is the situation ZIG's music is for.
pub fn music(n: i32, sit: Situation) void {
    if (n >= 1 and n <= 3) {
        zm.music(@intCast(n), sit);
        record(.music, @intCast(n));
        if (@import("zig_hooks.zig").zig) return;
        zg.requestSongTune(NAME, @intCast(n));
        resident = true;
    } else musicEnd(sit);
}

/// MUSIC OFF at a switch point: ZIG plays `next` from here.
pub fn musicEnd(next: Situation) void {
    zm.off(next);
    call(.music, 0);
}

/// MUSIC OFF inside an effect routine (the YM freed for it): no switch.
pub fn musicOff() void {
    zm.sndh_tune = 0;
    call(.music, 0);
}

pub fn samplay(n: i32) void {
    call(.samplay, @intCast(n & 0xFF));
}

pub fn samstop() void {
    call(.samstop, 0);
}

pub fn samloop(on: bool) void {
    call(.samloop, @intFromBool(on));
}

pub fn volume(v: i32) void {
    call(.volume, @truncate(@as(u32, @bitCast(v))));
}

pub fn noise(p: i32) void {
    call(.noise, @truncate(@as(u32, @bitCast(p))));
}

/// ENVEL shape, period: the period's two bytes, then the shape.
pub fn envel(shape: i32, period: i32) void {
    const p: u32 = @bitCast(period);
    call(.env_hi, @truncate(p >> 8));
    call(.env_lo, @truncate(p));
    call(.envel, @truncate(@as(u32, @bitCast(shape))));
}

pub fn reset() void {
    zm.reset();
    @import("zig_psg.zig").reset();
    resident = false;
    log_n = 0;
    log_total = 0;
    sent_n = 0;
}
