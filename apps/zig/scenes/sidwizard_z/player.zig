// --------------------------------------------------------------------------
// The player's driver: what the editor's playadapter.inc and keyhandler.inc do around the
// 6502 player, in Zig. The player itself (c64mem.zig runs it) is Hermit's, unchanged.
//   start  F1 / F3: a fresh C64, the tune image at MUSICDATA, inisub (the subtune), then the
//          adapter's resetJamIns (the selected instrument on every channel); F3 also switches
//          the player to pattern play (ptplyon) and sets each channel's pattern
//   tick   one 50 Hz frame: wCHDMOD($A0), playsub
//   pause  the adapter's `pause` (store the played instruments, resetJamIns: ADSR 0, gate off)
//          and `continue` (put them back)
// Addresses are the 64tass label listing of the 1.97 editor build (sw_player.bin).
// --------------------------------------------------------------------------
const swm = @import("swm.zig");
const mem = @import("c64mem.zig");

const INISUB: u16 = 0x1000;
const PLAYSUB: u16 = 0x1003;
const IPTNPLY: u16 = 0x101F;
const WCHDMOD: u16 = 0x1044;
const PTNCODE: u16 = 0x124C; // the player's `ldy SEQPOS,x` that pattern play overwrites with a JMP
const ADAPINS: u16 = 0x1CB5; // playadapter.adapins

const TEMPOPRGSUPP: u16 = 0x1A39;
const CURPTN: u16 = 0x3A;
const CURINS: u16 = 0x3E;
const SPDCNT: u16 = 0x26;
const TMPBASE: u16 = 0x64;
const TMPPOS: u16 = 0x65;
const PTNPOS: u16 = 0x28;
const PLAYMOD: u16 = 0xC67A; // playadapter.playmod: 0 jam, 1 song, 2 pattern (the player mutes by it)
const PLAYERINS: u16 = 0xC693; // playadapter.playerins: the instruments kept over a pause
const CHANNELS = [3]u8{ 0, 7, 14 };
const DOWN = [3]u8{ 14, 7, 0 }; // the adapter walks X = 14, 7, 0

pub const Mode = enum { stopped, song, pattern };

pub const Cfg = struct {
    mode: Mode,
    subtune: u8,
    selinst: u8,
    curptn: [3]u8 = .{ 1, 1, 1 },
};

pub const Error = error{ BadImage, DeadPlayer };

var frame: u64 = 0; // frames ticked: the player's frame k starts at cycle k x FRAME_CYCLES

/// The 6502's clock at the start of the next frame's call (waits for it, never goes back).
pub fn frameStart() u64 {
    return frame * FRAME_CYCLES;
}

/// Cycles of a PAL frame: 312 lines of 63.
pub const FRAME_CYCLES: u32 = 19656;

/// A fresh C64 with `song` as the player's tune, ready to tick from its start.
pub fn start(song: *const swm.Song, cfg: Cfg) Error!void {
    mem.reset();
    frame = 0;
    swm.toC64(song, mem.ram()[swm.music_data..]) catch return error.BadImage;
    // The editor initialised its player once at start-up (initune); F1/F3 then do it again over that
    // state (WFGHOST, PTNGATE and the instruments are already set), so both rounds run, the first silent.
    for (0..2) |round| {
        mem.ram()[PLAYMOD] = if (round == 0) 0 else if (cfg.mode == .pattern) 2 else 1;
        _ = mem.call(INISUB, .{ .a = cfg.subtune }) orelse return error.DeadPlayer;
        resetJamIns(cfg.selinst);
        if (round == 0) mem.takeWrites();
    }
    if (cfg.mode == .pattern) patternPlay(cfg.curptn);
}

/// resetJamIns: every channel plays the selected instrument, its ADSR zero and the gate off.
fn resetJamIns(selinst: u8) void {
    const r = mem.ram();
    for (DOWN) |x| {
        r[CURINS + x] = selinst;
        _ = mem.call(ADAPINS, .{ .x = x });
    }
}

/// ptplyon + f3play: the player loops the cursor's patterns instead of walking the orderlist.
fn patternPlay(curptn: [3]u8) void {
    const r = mem.ram();
    r[PTNCODE] = 0x4C; // JMP iPTNPLY
    r[PTNCODE + 1] = @truncate(IPTNPLY);
    r[PTNCODE + 2] = @truncate(IPTNPLY >> 8);
    for (CHANNELS, 0..) |x, c| {
        r[PTNPOS + x] = 0;
        r[SPDCNT + x] = 0xFF; // start with a row read
        r[CURPTN + x] = curptn[c];
        if (r[TEMPOPRGSUPP] & 0x80 != 0) r[TMPPOS + x] = r[TMPBASE + x];
    }
}

/// One frame of the player. Null: the CPU died (the caller stops the song).
pub fn tick() ?u32 {
    mem.waitUntil(frameStart());
    frame += 1;
    _ = mem.call(WCHDMOD, .{ .a = 0xA0 }) orelse return null; // LDY: chord playing on
    return mem.call(PLAYSUB, .{});
}

/// playadapter.pause: remember the played instruments, silence every channel.
pub fn pause(selinst: u8) void {
    mem.waitUntil(frameStart());
    const r = mem.ram();
    r[PLAYMOD] = 0;
    for (DOWN) |x| r[PLAYERINS + x] = r[CURINS + x]; // the editor's own x = 0/7/14 stride
    resetJamIns(selinst);
}

/// playadapter.continue: the played instruments back, the notes re-gated by the player's next rows.
pub fn unpause(mode: Mode) void {
    mem.waitUntil(frameStart());
    const r = mem.ram();
    r[PLAYMOD] = if (mode == .pattern) 2 else 1;
    for (DOWN) |x| {
        r[CURINS + x] = r[PLAYERINS + x];
        _ = mem.call(ADAPINS, .{ .x = x });
    }
}
