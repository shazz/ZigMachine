// --------------------------------------------------------------------------
// Where the B.I.G. digi tunes' PLAY keeps things (digi_big_play.zig).
//
// All six files (digital/ Ace 2, Labello, Phantom of the Asteroid, Sanxion,
// Starpaws, and big/Labello) hold the same driver: Mad Max's sequencer for the
// 3-voice mixer, assembled at a different address in each. Its code from PLAY
// on is byte for byte the same outside the absolute longs that relocation moves
// (prototypes/big_digi_re/holes.py), so every variable is found the same way:
// at a fixed offset from PLAY, in the operand of an instruction that uses it.
// They are read there, in RAM, once INIT has relocated them (`arm`).
//
// Grazey's INIT patches two things in this code, both checked: the
// `subi.l #$50000,d7` of the instrument's sample start becomes three nops, and
// the anti-rip check's beq (command 7) becomes a bra.
// --------------------------------------------------------------------------
const digi = @import("digi.zig");

pub const LEN: u32 = 0x5A6; // PLAY to the song's init ($44D26..$452CC in Ace 2)
// Every relocated long in [0, LEN), from holes.py (its first 54 of 75), plus the two patch sites.
const LONGS = [_]u32{ 0x2, 0x8, 0x12, 0x16, 0x1c, 0x26, 0x30, 0x3a, 0x44, 0x48, 0x4e, 0x5e, 0x68, 0x72, 0x78, 0x88, 0x92, 0x9c, 0xa2, 0xb2, 0xbc, 0xc6, 0xcc, 0xd6, 0xdc, 0xe2, 0xe8, 0xec, 0xf0, 0xf4, 0xf8, 0xfc, 0x100, 0x104, 0x108, 0x10c, 0x110, 0x114, 0x118, 0x11c, 0x120, 0x124, 0x128, 0x1a4, 0x1ca, 0x1fa, 0x228, 0x378, 0x3b4, 0x3e6, 0x40e, 0x42c, 0x454, 0x4b2, 0x4f6, 0x538, 0x548 };
const BRA: u32 = 0x152; // command 7's beq.w ($67), a bra.w ($60) once patched
const NOPS: u32 = 0x452; // subi.l #$50000,d7, three nops once patched
const VARS: u32 = 0x4BC; // the song's variables between the code ($451E2..$451F3): the instruments, transpose, on, patterns
pub const HOLES = blk: {
    var h: [LONGS.len + 3][2]u32 = undefined;
    for (LONGS, 0..) |at, i| h[i] = .{ at, at + 4 };
    h[LONGS.len] = .{ BRA, BRA + 1 };
    h[LONGS.len + 1] = .{ NOPS, NOPS + 6 };
    h[LONGS.len + 2] = .{ VARS, VARS + 0x12 };
    break :blk h;
};
pub const SIGNATURE: u64 = 0xBED9C90CAA036A91; // digi.maskedHash of [0, LEN), HOLES zeroed (big_digi_re/sig.py)
const FIRST: u16 = 0x5239; // addq.b #1,abs.l: the frame counter, the quick reject

/// What a command byte $80..$B7 does: its jump-table entry, by where it lands from PLAY.
pub const Cmd = enum { rest, rest_arg, rest_vol, nop, speed19, vib, slide_up, slide_down, track, skip3, transpose, flag1, tie };
const TARGETS = [_]struct { u32, Cmd }{
    .{ 0x244, .rest },  .{ 0x220, .nop },   .{ 0x224, .speed19 },    .{ 0x230, .nop },
    .{ 0x1E0, .vib },   .{ 0x214, .slide_up }, .{ 0x210, .slide_down }, .{ 0x136, .track },
    .{ 0x202, .skip3 }, .{ 0x1F8, .transpose }, .{ 0x1DA, .rest_arg }, .{ 0x234, .flag1 },
    .{ 0x12C, .tie },   .{ 0x23C, .rest_vol },
};
pub const CMDS = 17; // the table's length: a higher command would jump into code

/// The driver's variables, relocated, and its command table decoded.
pub const At = struct {
    cnt: u32, // byte: frames played
    on: u32, // byte: the song runs
    cur: u32, // byte, copied to cur + 1 each frame (command 2 sets it)
    cur2: u32,
    tick: u32, // byte: frames to the next row
    speed: u32, // byte: its reload
    v: [3]u32, // the voices, $4A bytes each
    silence: u32, // where a silent voice's pointer goes
    step: [3]u32, // the handler's addi.l immediates
    jt: u32, // the command table
    pat: u32, // long: the pattern table
    cf1: u32, // byte, command $FD of a track
    trans: u32, // byte: the global transpose
    arp: u32, // the arpeggio tables
    env: [2]u32, // the two envelope-table sets
    ins: u32, // long: the instrument table
    freq: u32, // 128 longs: a note's step
    cmd: [CMDS]Cmd,
};

/// The image's PLAY (the SNDH header's third bra), if it is this driver's.
pub fn playOf(image: []const u8) ?u32 {
    if (image.len < 12 or digi.be16(image, 8) != 0x6000) return null;
    const at = 10 + @as(u32, digi.be16(image, 10));
    if (at + LEN > image.len or digi.be16(image, at) != FIRST) return null;
    return if (digi.maskedHash(image[at..][0..LEN], &HOLES) == SIGNATURE) at else null;
}

/// PLAY's code at `play` in RAM, relocated by INIT, for the handler at `handler`: its
/// variables, or null if it is not the driver any more (Musashi plays it).
pub fn arm(comptime Bus: type, play: u32, handler: u32) ?At {
    const m = digi.Access(Bus);
    var code: [LEN]u8 = undefined;
    for (&code, 0..) |*b, i| b.* = Bus.read8(play + @as(u32, @intCast(i)));
    if (digi.be16(&code, 0) != FIRST or digi.maskedHash(&code, &HOLES) != SIGNATURE) return null;
    if (code[BRA] != 0x60) return null; // Grazey's bra over the anti-rip check
    for (0..3) |i| if (digi.be16(&code, NOPS + 2 * i) != 0x4E71) return null;
    const l = struct {
        fn at(c: *const [LEN]u8, off: u32) u32 {
            return digi.be32(c, off);
        }
    }.at;
    var a: At = .{
        .cnt = l(&code, 0x2),       .on = l(&code, 0x8),     .cur = l(&code, 0x12), .cur2 = l(&code, 0x16),
        .tick = l(&code, 0x1C),     .speed = l(&code, 0x44), .v = .{ l(&code, 0x26), l(&code, 0x30), l(&code, 0x3A) },
        .silence = l(&code, 0x5E),  .step = .{ l(&code, 0x68), l(&code, 0x92), l(&code, 0xBC) },
        .jt = l(&code, 0x4B2),      .pat = l(&code, 0x1CA),  .cf1 = l(&code, 0x1A4), .trans = l(&code, 0x1FA),
        .arp = l(&code, 0x378),     .env = .{ l(&code, 0x3B4), l(&code, 0x3E6) }, .ins = l(&code, 0x42C),
        .freq = l(&code, 0x548),    .cmd = undefined,
    };
    // The same variable named twice must be the same address; the steps must be the handler's.
    if (l(&code, 0x72) != a.step[0] or l(&code, 0x4F6) != a.trans or l(&code, 0x228) != a.cur) return null;
    if (l(&code, 0x40E) != a.speed or l(&code, 0x48) != a.tick) return null;
    const big = @import("digi_big.zig");
    for (a.step, big.STEP) |s, off| if (s != handler + off) return null;
    for (&a.cmd, 0..) |*c, i| c.* = decode(m.rd32(a.jt + 4 * @as(u32, @intCast(i))) -% play) orelse return null;
    return a;
}

fn decode(off: u32) ?Cmd {
    for (TARGETS) |t| if (t[0] == off) return t[1];
    return null;
}
