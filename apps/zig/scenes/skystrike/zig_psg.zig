// --------------------------------------------------------------------------
// ZIG mode's PSG: STOS's VOLUME / NOISE / ENVEL (the engine note) written
// straight to the YM2149 with zg.ymWrite. ZIG plays a MOD, not skystrike.sndh,
// so there is no 68000 image to send these commands to, and the YM is idle
// under a MOD (libs/zig/players/sfx_voice.zig mixes it with the song).
//
// Register for register what sound.s does with them (its volume / noise /
// envel, transcribed from STOS at $2EE12 / $2EE3E / $2EDEE), but for the
// level: VOLUME sets only zig_settings.psg_voices of the three voices, the
// rest 0, so the engine does not drown the effects over the MOD:
//   VOLUME v   8, 9, 10 = v (on the first psg_voices; 3 = sound.s)
//   NOISE p    6 = p & 31; 0-5 = 0; 7 = $C0; 13 rewritten with its value
//   ENVEL s,p  11 = p low, 12 = p high, 13 = s & 15
// A change to those routines in sound.s must be made here too.
//
// A register already holding the value is not written again (13 always is:
// writing it restarts the envelope). What the chip holds is forgotten when a
// new song is requested (invalidate): an SNDH in between reset the YM.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const sound = @import("sound.zig");
const set = @import("zig_settings.zig");

var regs: [14]u8 = [_]u8{0} ** 14;
var known: [14]bool = [_]bool{false} ** 14;
var env_period: u16 = 0;
/// Commands zg.ymWrite refused (the queue was full): checked 0 by the harness.
pub var refused: u32 = 0;

/// One of the game's PSG commands (sound.zig's ops 4-8).
pub fn command(op: sound.Op, arg: u8) void {
    switch (op) {
        .volume => for (0..3) |i| write(@intCast(8 + i), if (i < set.psg_voices) arg else 0),
        .noise => noise(arg),
        .env_hi => env_period = @as(u16, arg) << 8 | (env_period & 0xFF),
        .env_lo => env_period = (env_period & 0xFF00) | arg,
        .envel => {
            write(11, @truncate(env_period));
            write(12, @truncate(env_period >> 8));
            write(13, arg & 15);
        },
        else => {},
    }
}

fn noise(p: u8) void {
    write(6, p & 31);
    for (0..6) |r| write(@intCast(r), 0);
    write(7, 0xC0);
    write(13, regs[13]);
}

fn write(reg: u8, val: u8) void {
    if (reg != 13 and known[reg] and regs[reg] == val) return;
    regs[reg] = val;
    known[reg] = true;
    if (!zg.ymWrite(reg, val)) refused +%= 1;
}

/// The YM's contents are no longer ours to know (a song was requested).
pub fn invalidate() void {
    known = [_]bool{false} ** 14;
}

// ---- the engine note across a Z switch -----------------------------------
// The switch loads the other mode's song, which silences the YM, and the game
// sets its engine note again only when it next changes. So the game's last
// PSG commands outside an effect routine are kept, in both modes, and a
// switch replays them onto the new song: VOLUME, NOISE, ENVEL in the order
// sfx.zig's 990 sends them.
const Last = struct { volume: ?u8 = null, noise: ?u8 = null, hi: u8 = 0, lo: u8 = 0, shape: ?u8 = null };
var last: Last = .{};

/// One of the game's commands outside an effect routine (sound.zig).
pub fn remember(op: sound.Op, arg: u8) void {
    switch (op) {
        .volume => last.volume = arg,
        .noise => last.noise = arg,
        .env_hi => last.hi = arg,
        .env_lo => last.lo = arg,
        .envel => last.shape = arg,
        else => {},
    }
}

/// After Z: the engine note onto the YM (ZIG) or the SNDH just loaded.
pub fn replay(zig: bool) void {
    const send = if (zig) &command else &sound.send;
    if (last.volume) |v| send(.volume, v);
    if (last.noise) |n| send(.noise, n);
    if (last.shape) |sh| {
        send(.env_hi, last.hi);
        send(.env_lo, last.lo);
        send(.envel, sh);
    }
}

/// Power-on: nothing written yet.
pub fn reset() void {
    invalidate();
    regs = [_]u8{0} ** 14;
    env_period = 0;
    refused = 0;
    last = .{};
}
