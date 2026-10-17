// --------------------------------------------------------------------------
// Wow Scroller (MAN Cool, 1989; ripped and converted by Grazey): the Union
// Demo's TCB2 WOW!-SCROLLER tune, natively. Beat Dis's sibling: one sample
// byte a Timer A interrupt through the same 256-entry volume table (indexed
// by the byte itself, no `addi.b #$80`), at 2457600 / 4 / 81 = 7585 Hz, and a
// playlist of segments the 50 Hz play moves on. Offsets are the file's.
//
//   init   (first time, word $A0) the _MCH cookie looked up ($268), the 15
//          rows at $B78 (start, length, -) made a playlist of absolute
//          (start, end) at $AF8, -1 terminated; then entry 0, the YM's 0-10
//          zeroed and 7 = $FF, the vector and 5 MFP bytes saved at $2EC, the
//          handler $202 installed, Timer A /4, 81
//   play   once the pointer is past the segment's end, the next entry (-1:
//          entry 0). Checked only here: the handler plays on past the end
//          until the next play, as on Beat Dis. Kept.
//   exit   Timer A stopped, the vector and MFP bytes back, volumes off
//   irq    ($202) `movep.l` + `movep.w`: registers 8, 9, 10 from the table
//
// The init picks the handler by `cmpa.w #3,a0` on the ADDRESS of its machine
// word, never 3: always $202 (its $232 twin is dead code). Every access is
// the 68000's, in its order, so Musashi and this agree on RAM as well as YM.
// --------------------------------------------------------------------------
const digi = @import("digi.zig");
const sndh = @import("sndh.zig");

pub const CUR: u32 = 0x92; // pointer, then END: the segment playing
pub const END: u32 = 0x96;
const IDX: u32 = 0x9E; // the playlist entry (word)
const FLAG: u32 = 0xA0; // init has expanded the rows (word)
pub const HANDLER: u32 = 0x202;
const MCH: u32 = 0x2EA; // word: what the _MCH cookie said
const SAVE: u32 = 0x2EC; // the old $134 vector, then TACR VR IERA IMRA TADR
pub const TABLE: u32 = 0x2F8;
const PLAYLIST: u32 = 0xAF8;
const SEQ: u32 = 0xB78; // 12 bytes a row: start, length (from DATA), unused
pub const DATA: u32 = 0xC32;
const MAX_ROWS: u32 = (SEQ - PLAYLIST) / 8 - 1; // room for the -1 terminator

const CODE: u32 = 0x68; // the header's three stubs, then everything to the table
const HOLES = [_][2]u32{ .{ CUR - CODE, FLAG + 2 - CODE }, .{ MCH - CODE, TABLE - CODE } };
const SIGNATURE: u64 = 0xAED3E628C840C04D; // digi.maskedHash of [CODE, TABLE), its state zeroed
pub const HZ: f32 = 2457600.0 / 4.0 / 81.0;

pub const Driver = struct {
    base: u32, // the image's 68000 address
};

pub fn match(image: []const u8, base: u32) ?Driver {
    if (image.len < DATA) return null;
    for ([_]u32{ 0x6000_0066, 0x6000_0070, 0x6000_007A }, 0..) |br, i| if (digi.be32(image, 4 * i) != br) return null;
    if (digi.maskedHash(image[CODE..TABLE], &HOLES) != SIGNATURE) return null;
    return .{ .base = base };
}

/// The rows fit the playlist and their samples the image (what init expands).
pub fn tablesFit(image: []const u8) bool {
    var row: u32 = SEQ;
    var n: u32 = 0;
    while (row < DATA and image[row] < 0x80) : (row += 12) {
        const start = digi.be32(image, row);
        const len = digi.be32(image, row + 4);
        n += 1;
        if (n > MAX_ROWS or start > image.len - DATA or len > image.len - DATA - start) return false;
    }
    return row < DATA and n > 0;
}

pub fn call(comptime Bus: type, d: Driver, entry: u32) void {
    switch (entry) {
        sndh.INIT => init(Bus, d.base),
        sndh.EXIT => exit(Bus, d.base),
        else => play(Bus, d.base),
    }
}

const PSG: u32 = 0xFF8800;
const MFP: u32 = 0xFFFA00;
const VEC_TIMER_A: u32 = 0x134;
const SAVED = [_]u32{ 0x19, 0x17, 0x07, 0x13, 0x1F }; // TACR VR IERA IMRA TADR

fn init(comptime Bus: type, b: u32) void {
    const m = digi.Access(Bus);
    if (m.rd16(b + FLAG) == 0) {
        m.wr16(b + FLAG, 1);
        cookie(Bus, b);
        expand(Bus, b);
    }
    m.wr32(b + CUR, m.rd32(b + PLAYLIST));
    m.wr32(b + END, m.rd32(b + PLAYLIST + 4));
    var r: u8 = 11;
    while (r > 0) {
        r -= 1;
        m.wr8(PSG, r);
        m.wr8(PSG + 2, 0);
    }
    m.wr8(PSG, 0);
    m.wr8(PSG + 2, 0);
    m.wr8(PSG, 7);
    m.wr8(PSG + 2, 0xFF);
    m.wr32(b + SAVE, m.rd32(VEC_TIMER_A));
    for (SAVED, 0..) |reg, i| m.wr8(b + SAVE + 4 + @as(u32, @intCast(i)), m.rd8(MFP + reg));
    m.wr32(VEC_TIMER_A, b + HANDLER);
    m.wr8(MFP + 0x19, 0); // TACR: stop
    m.bclr(MFP + 0x17, 3); // VR: automatic end of interrupt
    m.bset(MFP + 0x07, 5); // IERA, IMRA: Timer A on
    m.bset(MFP + 0x13, 5);
    m.wr8(MFP + 0x19, 1); // /4
    m.wr8(MFP + 0x1F, 0x51); // 81
}

/// $268: the _MCH cookie's machine, as a word at MCH (0 with no cookie jar).
fn cookie(comptime Bus: type, b: u32) void {
    const m = digi.Access(Bus);
    const jar = m.rd32(0x5A0);
    var kind: u16 = 0;
    if (jar != 0) {
        var a = jar;
        while (m.rd32(a) != 0 and m.rd32(a) != 0x5F4D4348) a +%= 8;
        if (m.rd32(a) != 0) kind = switch (m.rd32(a +% 4)) {
            0x30000 => 3,
            0x10000 => 1,
            0x10010 => 2,
            0x20000 => 4,
            else => 0,
        };
    }
    m.wr16(b + MCH, kind);
}

/// $B4: each row's (start, start + length), made absolute, then -1, -1.
fn expand(comptime Bus: type, b: u32) void {
    const m = digi.Access(Bus);
    var row = b + SEQ;
    var out = b + PLAYLIST;
    while (true) {
        m.wr32(out, m.rd32(row));
        m.wr32(out + 4, m.rd32(row));
        m.wr32(out + 4, m.rd32(out + 4) +% m.rd32(row + 4));
        m.wr32(out, m.rd32(out) +% (b + DATA));
        m.wr32(out + 4, m.rd32(out + 4) +% (b + DATA));
        out += 8;
        row += 12;
        if (m.rd8(row) & 0x80 != 0) break;
    }
    m.wr32(out, 0xFFFF_FFFF);
    m.wr32(out + 4, 0xFFFF_FFFF);
}

fn play(comptime Bus: type, b: u32) void {
    const m = digi.Access(Bus);
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

fn exit(comptime Bus: type, b: u32) void {
    const m = digi.Access(Bus);
    m.wr8(MFP + 0x19, 0);
    m.wr32(VEC_TIMER_A, m.rd32(b + SAVE));
    for (SAVED, 0..) |reg, i| m.wr8(MFP + reg, m.rd8(b + SAVE + 4 + @as(u32, @intCast(i))));
    for ([_]u32{ 8, 9, 10 }) |r| m.wr32(PSG, r << 24);
}

/// One interrupt ($202). `movep.l d1,0(a1)`: select, value, select, value on
/// $8800/$8802/$8804/$8806 (the PSG's mirrors); then `movep.w d0` for 10.
pub fn irq(comptime Bus: type, d: Driver) void {
    const m = digi.Access(Bus);
    const pos = m.rd32(d.base + CUR);
    const s = m.rd8(pos);
    m.wr32(d.base + CUR, pos +% 1);
    const e = d.base + TABLE + @as(u32, s) * 8;
    const hi = m.rd32(e);
    const lo = m.rd16(e + 4);
    for (0..4) |i| m.wr8(PSG + 2 * @as(u32, @intCast(i)), @truncate(hi >> @intCast(24 - 8 * i)));
    m.wr8(PSG, @truncate(lo >> 8));
    m.wr8(PSG + 2, @truncate(lo));
}
