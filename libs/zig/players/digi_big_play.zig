// --------------------------------------------------------------------------
// The B.I.G. digi tunes' PLAY, natively (Mad Max's sequencer for his 3-voice
// mixer; the rip is prototypes/big_digi_re/, the addresses digi_big_map.zig).
//
// PLAY writes no hardware: per voice it reads its pattern stream and sets the
// mixer's state, the sample pointer at $380/$386/$38C and the step the handler
// adds every interrupt (the handler's own addi.l immediate, self-modifying).
// So this is RAM in, RAM out, every access the 68000's, in its order, and the
// 68000 can take over (or this from it) between any two calls.
//
// A voice is $4A bytes (Ace 2's at $44C02, $44C4C, $44C96):
//   $00 flags   b1 b2 vibrato, b3 slide, b5 new note, b7 slide up, b0 toggles
//   $02 the pattern pointer    $06 the track's start   $0A the track position
//   $0E slide   $0F tie        $10/$14 arpeggio table, pointer   $18/$19 vibrato
//   $1A arpeggio speed  $1B frames left in the note  $1C the note's length
//   $1D note    $1E on   $1F arpeggio count   $26/$25 a byte copied each note
//   $27 instrument flags  $28 transpose  $29 b0 note decay, b1 env set 2
//   $2B/$2C envelope count, speed  $2D fine  $2E/$32 envelope pointer, start
//   $36 loop flag, $38 loop length (the handler's)  $3C vibrato  $40 -> $38x
//   $44 the sample's start  $48 instrument bank  $52 (= the next voice's $08)
// --------------------------------------------------------------------------
const digi = @import("digi.zig");
const map = @import("digi_big_map.zig");
const note = @import("digi_big_note.zig");
const At = map.At;

/// Mutant 12 (sndh_native.zig, test only): a duration byte $E0..$FF one frame short.
pub var short_note: bool = false;
/// A command past the table (it would jump into code): the voice stops being read.
pub var lost: bool = false;

pub fn play(comptime Bus: type, at: *const At) void {
    const m = digi.Access(Bus);
    m.wr8(at.cnt, m.rd8(at.cnt) +% 1);
    if (m.rd8(at.on) != 0) {
        m.wr8(at.cur2, m.rd8(at.cur));
        const t = m.rd8(at.tick) -% 1;
        m.wr8(at.tick, t);
        if (t == 0) {
            for (at.v) |v| tick(Bus, at, v);
            m.wr8(at.tick, m.rd8(at.speed));
        }
        const PTR = [3]u32{ 0x380, 0x386, 0x38C };
        for (at.v, PTR, at.step) |v, p, s| {
            const r = note.compute(Bus, at, v);
            if (r.on == 0) {
                m.wr32(p, at.silence);
                m.wr32(s, 0);
            } else m.wr32(s, r.step);
        }
    }
    if (m.rd8(at.on) == 0) for (at.step) |s| m.wr32(s, 0);
}

/// $44F78: a voice's frame. The note's frames run out: the next row of its pattern.
fn tick(comptime Bus: type, at: *const At, v: u32) void {
    const m = digi.Access(Bus);
    const t = m.rd8(v + 0x1B) -% 1;
    m.wr8(v + 0x1B, t);
    if (t != 0) return slide(Bus, v);
    m.wr8(v + 0x0F, 0);
    m.wr8(v + 0x1E, 0x0F);
    m.wr8(v, 0);
    row(Bus, at, v, m.rd32(v + 2));
}

/// $45042: a slide moves the note every frame of it.
fn slide(comptime Bus: type, v: u32) void {
    const m = digi.Access(Bus);
    if (!m.btst(v, 3)) return;
    const d5 = m.rd8(v + 0x0E);
    const n = m.rd8(v + 0x1D);
    m.wr8(v + 0x1D, if (m.btst(v, 7)) n +% d5 else n -% d5);
}

/// Where the stream goes on: $44F94 (the next byte), $44FA8 (a note), $44FD4 (the row's end).
pub const Next = enum { byte, note, end };

/// $44F94: bytes of the pattern at `start` up to a note or a rest.
fn row(comptime Bus: type, at: *const At, v: u32, start: u32) void {
    const m = digi.Access(Bus);
    var a1 = start;
    var next: Next = .byte;
    while (true) switch (next) {
        .byte => {
            const c = m.rd8(a1);
            a1 +%= 1;
            if (c & 0x80 != 0) {
                next = command(Bus, at, v, c, &a1) orelse return;
                continue;
            }
            m.bclr(v + 0x24, 2);
            m.wr8(v + 0x1D, c);
            next = .note;
        },
        .note => { // $44FA8
            if (m.rd8(v + 0x0F) == 0) {
                m.wr32(v + 0x2E, m.rd32(v + 0x32));
                m.wr8(v + 0x2B, m.rd8(v + 0x2C));
                if (m.rd8(v + 0x1E) != 0) m.wr32(m.rd32(v + 0x40), m.rd32(v + 0x44));
            }
            m.bset(v, 5);
            next = .end;
        },
        .end => return end(Bus, v, a1),
    };
}

/// $44FD4: the note's length, the instrument's flags, the pattern pointer kept.
fn end(comptime Bus: type, v: u32, a1: u32) void {
    const m = digi.Access(Bus);
    m.wr8(v + 0x1B, m.rd8(v + 0x1C));
    m.wr8(v + 0x30, m.rd8(v + 0x32));
    if (m.rd8(v + 0x0F) == 0) m.wr8(v + 0x31, 0);
    _ = note.flags(Bus, v);
    m.wr8(v + 0x1F, m.rd8(v + 0x1A));
    m.wr8(v + 0x25, m.rd8(v + 0x26));
    m.wr32(v + 2, a1);
    if (m.rd8(v + 0x0F) == 0) m.wr32(v + 0x14, m.rd32(v + 0x10));
}

/// $45064: a byte with bit 7 set. Null: a command past the table (`lost`).
fn command(comptime Bus: type, at: *const At, v: u32, c: u8, a1: *u32) ?Next {
    const m = digi.Access(Bus);
    if (c >= 0xE0) { // a length
        m.wr8(v + 0x1C, if (short_note) c +% 0x20 else c +% 0x21);
        return .byte;
    }
    if (c >= 0xC0) return note.instrument(Bus, at, v, (c & 0x0F) + (if (c >= 0xD0) @as(u8, 0x10) else 0), a1);
    if (c >= 0xB8) { // the speed: 1..8
        m.wr8(at.speed, c +% 0x49);
        return .byte;
    }
    const i = c & 0x7F;
    if (i >= map.CMDS) {
        lost = true;
        return null;
    }
    return note.cmd(Bus, at, v, at.cmd[i], a1);
}
