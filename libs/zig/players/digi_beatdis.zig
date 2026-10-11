// --------------------------------------------------------------------------
// Beat Dis! (MAN Cool, 1989; converted by Grazey): its sequencer, init / play /
// exit, natively. The sample bytes go out through digi_handler.zig at 15753.85 Hz
// (Timer A, /4, data $27). The static rip and the table layout are in
// prototypes/beatdis_re/README.md.
//
//   init   the first time only, expand the 69-row sequence (count, sample) into a
//          playlist of absolute (start, end) pairs, -1 terminated; then play
//          entry 0, silence the YM, save the vector and MFP bytes, start Timer A
//   play   (50 Hz) once the pointer is past the segment's end, take the next
//          entry (-1 wraps to 0). Only checked here, so the handler plays on past
//          `end` until the next VBL: up to 315 bytes of what follows. Kept.
//   exit   restore what init saved, volumes off
//
// Every access is the 68000's, in its order, on the SNDH player's bus: the
// state words live where the tune keeps them, so Musashi and this agree on RAM
// as well as on the YM.
// --------------------------------------------------------------------------
const digi = @import("digi.zig");
const handler = @import("digi_handler.zig");
const sndh = @import("sndh.zig");

// Offsets from the code's start (where the header's INIT branch lands).
const CUR: u32 = 0x2A; // pointer, then END: the segment playing
const END: u32 = 0x2E;
const IDX: u32 = 0x36; // the playlist entry (word)
const FLAG: u32 = 0x38; // init has expanded the sequence (word)
const HANDLER: u32 = 0x1B4;
const SAVE: u32 = 0x206; // the old $134 vector, then TACR VR IERA IMRA TADR
const TABLE: u32 = 0x212;
const PLAYLIST: u32 = 0xA12;
const SEQ: u32 = 0xE5E;
const SAMP: u32 = 0xF7E; // 24 bytes a sample: start, end (from DATA), name
const DATA: u32 = 0x125A;

const LEN: u32 = HANDLER; // the stubs, the state words, init, play, exit
const HOLES = [_][2]u32{.{ CUR, FLAG + 2 }};
const SIGNATURE: u64 = 0xC674036E0DEF2CE5; // digi.maskedHash of Beat Dis's
const MAX_ENTRIES: u32 = (SEQ - PLAYLIST) / 8 - 1; // room for the -1 terminator

const PSG: u32 = 0xFF8800;
const MFP: u32 = 0xFFFA00;
const VEC_TIMER_A: u32 = 0x134;

pub const Driver = struct {
    base: u32, // the code's 68000 address
    handler: handler.Handler,
};

/// `bra.w` at image offset `off`: its target offset.
fn branch(image: []const u8, off: usize) ?u32 {
    if (digi.be16(image, off) != 0x6000) return null;
    return digi.pcRel(@intCast(off), digi.be16(image, off + 2));
}

pub fn match(image: []const u8, base: u32) ?Driver {
    if (image.len < 12) return null;
    const code = branch(image, sndh.INIT) orelse return null;
    if (branch(image, sndh.EXIT) != code + 0x0E or branch(image, sndh.PLAY) != code + 0x1C) return null;
    if (code + DATA > image.len) return null;
    if (digi.maskedHash(image[code..][0..LEN], &HOLES) != SIGNATURE) return null;
    const h = handler.match(image, base, code + HANDLER) orelse return null;
    return .{ .base = base + code, .handler = h };
}

/// Where the sample bytes start (every playlist entry points at or past it).
pub fn samples(d: Driver) u32 {
    return d.base + DATA;
}

/// The handler reads this sequencer's state and table, and init's expansion
/// stays in the playlist buffer and points into the image.
pub fn tablesFit(image: []const u8, base: u32, d: Driver) bool {
    const code = d.base - base;
    if (d.handler.cur != d.base + CUR or d.handler.table != d.base + TABLE) return false;
    var row: u32 = code + SEQ;
    var entries: u32 = 0;
    while (row < code + SAMP and image[row] < 0x80) : (row += 4) {
        const count = image[row];
        const samp = code + SAMP + @as(u32, image[row + 1]) * 24;
        entries += count;
        if (count == 0 or entries > MAX_ENTRIES or samp + 8 > image.len) return false;
        const start = digi.be32(image, samp);
        const end = digi.be32(image, samp + 4);
        if (start > end or end > image.len - code - DATA) return false;
    }
    return row < code + SAMP;
}

pub fn call(comptime Bus: type, d: Driver, entry: u32) void {
    switch (entry) {
        sndh.INIT => init(Bus, d),
        sndh.EXIT => exit(Bus, d),
        else => play(Bus, d),
    }
}

fn init(comptime Bus: type, d: Driver) void {
    const m = digi.Access(Bus);
    const b = d.base;
    if (m.rd16(b + FLAG) == 0) {
        m.wr16(b + FLAG, 1);
        expand(Bus, d);
    }
    m.wr32(b + CUR, m.rd32(b + PLAYLIST));
    m.wr32(b + END, m.rd32(b + PLAYLIST + 4));
    for (0..6) |r| m.wr32(PSG, @as(u32, @intCast(r)) << 24);
    Bus.write8(PSG, 7);
    const mixer = (Bus.read8(PSG) & 0xC0) | 0x3F;
    Bus.write8(PSG, 7);
    Bus.write8(PSG + 2, mixer);
    m.wr32(b + SAVE, m.rd32(VEC_TIMER_A));
    for ([_]u32{ 0x19, 0x17, 0x07, 0x13, 0x1F }, 0..) |reg, i| Bus.write8(b + SAVE + 4 + @as(u32, @intCast(i)), Bus.read8(MFP + reg));
    m.wr32(VEC_TIMER_A, d.handler.addr);
    Bus.write8(MFP + 0x19, 0); // TACR: stop
    Bus.write8(MFP + 0x17, Bus.read8(MFP + 0x17) & ~@as(u8, 8)); // VR: automatic end of interrupt
    Bus.write8(MFP + 0x07, Bus.read8(MFP + 0x07) | 0x20); // IERA, IMRA: Timer A on
    Bus.write8(MFP + 0x13, Bus.read8(MFP + 0x13) | 0x20);
    Bus.write8(MFP + 0x19, 1); // /4
    Bus.write8(MFP + 0x1F, 0x27); // 2457600 / 4 / 39 = 15753.85 Hz
}

/// The sequence's rows into the playlist: `count` copies of each sample's
/// (start, end), made absolute. tablesFit has bounded it.
fn expand(comptime Bus: type, d: Driver) void {
    const m = digi.Access(Bus);
    const data = d.base + DATA;
    var row = d.base + SEQ;
    var out = d.base + PLAYLIST;
    while (true) : (row += 4) {
        var n: u16 = @as(u16, Bus.read8(row)) -% 1; // dbra: count times
        while (true) : (n -= 1) {
            const samp = d.base + SAMP + @as(u32, Bus.read8(row + 1)) * 0x18;
            m.wr32(out, m.rd32(samp));
            m.wr32(out + 4, m.rd32(samp + 4));
            m.wr32(out, m.rd32(out) +% data);
            m.wr32(out + 4, m.rd32(out + 4) +% data);
            out += 8;
            if (n == 0) break;
        }
        if (Bus.read8(row + 4) & 0x80 != 0) break;
    }
    m.wr32(out, 0xFFFF_FFFF);
    m.wr32(out + 4, 0xFFFF_FFFF);
}

fn play(comptime Bus: type, d: Driver) void {
    const m = digi.Access(Bus);
    const b = d.base;
    const pos: i32 = @bitCast(m.rd32(b + CUR));
    const end: i32 = @bitCast(m.rd32(b + END));
    if (end >= pos) return;
    m.wr16(b + IDX, m.rd16(b + IDX) +% 1);
    while (true) {
        const off: i16 = @bitCast(m.rd16(b + IDX) << 3); // asl.w #3, then (a1,d1.w)
        const entry = b + PLAYLIST +% @as(u32, @bitCast(@as(i32, off)));
        if (m.rd32(entry) != 0xFFFF_FFFF) {
            m.wr32(b + CUR, m.rd32(entry));
            m.wr32(b + END, m.rd32(entry + 4));
            return;
        }
        m.wr16(b + IDX, 0);
    }
}

fn exit(comptime Bus: type, d: Driver) void {
    const m = digi.Access(Bus);
    Bus.write8(MFP + 0x19, 0);
    m.wr32(VEC_TIMER_A, m.rd32(d.base + SAVE));
    for ([_]u32{ 0x19, 0x17, 0x07, 0x13, 0x1F }, 0..) |reg, i| Bus.write8(MFP + reg, Bus.read8(d.base + SAVE + 4 + @as(u32, @intCast(i))));
    for ([_]u32{ 8, 9, 10 }) |r| m.wr32(PSG, r << 24);
}
