// --------------------------------------------------------------------------
// The B.I.G. digi PLAY's commands, instruments and the frame's note
// (digi_big_play.zig has the voice layout; the 68000 addresses are Ace 2's).
// The quirks are the 68000's and kept: a voice's note decay counts at $52(a0),
// which is the NEXT voice's byte $08; the decay reloads while the count is NOT
// zero; a vibrato depth 1..$7F is (depth - 256) * 16, not -depth * 16.
// --------------------------------------------------------------------------
const digi = @import("digi.zig");
const map = @import("digi_big_map.zig");
const At = map.At;
const Next = @import("digi_big_play.zig").Next;

/// $44E0E's commands. `a1` is the pattern pointer, past the command byte.
pub fn cmd(comptime Bus: type, at: *const At, v: u32, c: map.Cmd, a1: *u32) Next {
    const m = digi.Access(Bus);
    switch (c) {
        .nop => {},
        .speed19 => m.wr8(at.cur, 0x19),
        .vib => {
            m.wr32(v + 0x3C, 0);
            m.bset(v, 2);
            m.wr8(v + 0x18, take(Bus, a1));
            m.wr8(v + 0x19, take(Bus, a1));
        },
        .slide_down, .slide_up => {
            if (c == .slide_down) m.bset(v, 7);
            m.bset(v, 3);
            m.wr8(v + 0x0E, take(Bus, a1));
        },
        .track => a1.* = track(Bus, at, v),
        .skip3 => a1.* +%= 3,
        .transpose => m.wr8(at.trans, take(Bus, a1)),
        .flag1 => m.bset(v, 1),
        .tie => m.wr8(v + 0x0F, 1),
        .rest, .rest_arg, .rest_vol => { // $44F6A
            if (c == .rest_arg) a1.* +%= 1;
            if (c == .rest_vol) m.wr8(v + 0x26, take(Bus, a1));
            m.wr8(v + 0x1E, 0);
            m.bclr(v + 0x24, 2);
            return .end;
        },
    }
    return .byte;
}

fn take(comptime Bus: type, a1: *u32) u8 {
    const b = digi.Access(Bus).rd8(a1.*);
    a1.* +%= 1;
    return b;
}

/// $44E8C (command 7): the track's next entry, $80 a transpose, $FD a byte, $FE/$FF from the top.
fn track(comptime Bus: type, at: *const At, v: u32) u32 {
    const m = digi.Access(Bus);
    while (true) {
        var d0 = m.rd32(v + 0x0A);
        var a2 = m.rd32(v + 6) +% d0;
        d0 +%= 1;
        const c = m.rd8(a2);
        if (c == 0x80 or c == 0xFD) {
            if (c == 0x80) m.wr8(v + 0x28, m.rd8(a2 + 1)) else m.wr8(at.cf1, m.rd8(a2 + 1));
            m.wr32(v + 0x0A, m.rd32(v + 0x0A) +% 2);
            continue;
        }
        if (c == 0xFE or c == 0xFF) {
            a2 = m.rd32(v + 6);
            d0 = 1;
        }
        m.wr32(v + 0x0A, d0);
        return m.rd32(m.rd32(at.pat) +% @as(u32, m.rd8(a2)) * 4);
    }
}

/// $4514A: instrument `n` of the voice's bank: its sample, loop, fine, flags and tables.
pub fn instrument(comptime Bus: type, at: *const At, v: u32, n: u8, a1: *u32) Next {
    const m = digi.Access(Bus);
    const a2 = m.rd32(m.rd32(at.ins) +% @as(u32, n +% m.rd8(v + 0x48)) * 4);
    m.wr8(v + 0x2D, m.rd8(a2 +% 4));
    m.wr32(v + 0x38, m.rd16(a2 +% 2) -% m.rd16(a2));
    const start = m.rd32(a2 -% 4); // Grazey's nops: no subi.l #$50000
    m.wr32(m.rd32(v + 0x40), start);
    m.wr32(v + 0x44, start);
    m.wr8(v + 0x27, m.rd8(a2 -% 6));
    tables(Bus, at, v, m.rd8(a2 -% 5));
    if (!flags(Bus, v)) return .byte;
    a1.* +%= 1;
    return .note;
}

/// The instrument flags' two settings ($44FEE and $45192). True: bit 1 (a fixed note $10).
pub fn flags(comptime Bus: type, v: u32) bool {
    const m = digi.Access(Bus);
    if (m.btst(v + 0x27, 0)) {
        m.wr16(v + 0x3C, 0);
        m.bset(v, 2);
        m.wr8(v + 0x18, 0x48);
        m.wr8(v + 0x19, 1);
    }
    if (!m.btst(v + 0x27, 1)) return false;
    m.bset(v, 1);
    m.wr8(v + 0x1D, 0x10);
    return true;
}

/// $45088: below $80 an arpeggio table; $80..$8F / $90.. an envelope of set 1 / 2, then arpeggio 0.
fn tables(comptime Bus: type, at: *const At, v: u32, d0: u8) void {
    const m = digi.Access(Bus);
    if (d0 >= 0x80) {
        const two = d0 >= 0x90;
        if (two) m.bset(v + 0x29, 1) else m.bclr(v + 0x29, 1);
        const p = m.rd32(at.env[@intFromBool(two)] +% @as(u32, d0 & 0x0F) * 4);
        m.wr32(v + 0x2E, p);
        m.wr32(v + 0x32, p);
        m.wr8(v + 0x2B, m.rd8(p -% 1));
        m.wr8(v + 0x2C, m.rd8(v + 0x2B));
        return tables(Bus, at, v, 0);
    }
    const p = m.rd32(at.arp +% @as(u32, d0) * 4);
    m.wr32(v + 0x14, p);
    m.wr32(v + 0x10, p);
    m.wr8(v + 0x1A, m.rd8(m.rd32(v + 0x10) -% 1));
    m.wr8(v + 0x1F, m.rd8(v + 0x1A));
}

pub const Out = struct { step: u32, on: u8 };

/// $451F4: the voice's step this frame (its note through the arpeggio, the envelope and the
/// vibrato) and whether it sounds.
pub fn compute(comptime Bus: type, at: *const At, v: u32) Out {
    const m = digi.Access(Bus);
    if (m.btst(v + 0x29, 0)) {
        const t = m.rd8(v + 0x52) -% 1;
        m.wr8(v + 0x52, t);
        if (t != 0) {
            m.wr8(v + 0x52, m.rd8(v + 0x2A));
            m.wr8(v + 0x1D, m.rd8(v + 0x1D) -% 1);
        }
    }
    var d7 = m.rd8(v);
    var d0 = m.rd8(v + 0x1D) +% m.rd8(at.trans);
    const f = m.rd8(v + 0x1F);
    m.wr8(v + 0x1F, f -% 1);
    if (f == 0) d0 +%= arpeggio(Bus, v);
    d0 = @import("digi_big_env.zig").env(Bus, at, v, d0 +% m.rd8(v + 0x28));
    d0 +%= m.rd8(v + 0x2D);
    var step = m.rd32(at.freq +% @as(u32, d0 & 0x7F) * 4);
    d7 ^= 1;
    m.wr8(v, d7);
    if (d7 & 4 != 0) {
        const d4 = m.rd8(v + 0x19) -% 1;
        if (d4 != 0) {
            m.wr8(v + 0x19, d4);
        } else {
            const b = m.rd8(v + 0x18);
            const d6: u32 = if (b & 0x80 != 0) @as(u32, b) << 4 else 0 -% (@as(u32, 0 -% b) << 4);
            const acc = d6 +% m.rd32(v + 0x3C);
            m.wr32(v + 0x3C, acc);
            step +%= acc;
        }
    }
    return .{ .step = step, .on = m.rd8(v + 0x1E) };
}

/// The arpeggio's next byte ($45228): $8F goes back to the table's start, $8E holds the last.
fn arpeggio(comptime Bus: type, v: u32) u8 {
    const m = digi.Access(Bus);
    m.wr8(v + 0x1F, m.rd8(v + 0x1A));
    var a1 = m.rd32(v + 0x14);
    var d1 = m.rd8(a1);
    if (d1 == 0x8F) {
        a1 = m.rd32(v + 0x10);
        d1 = m.rd8(a1);
    }
    if (d1 == 0x8E) {
        a1 -%= 1;
        d1 = m.rd8(a1);
    }
    m.wr32(v + 0x14, a1 +% 1);
    return d1;
}
