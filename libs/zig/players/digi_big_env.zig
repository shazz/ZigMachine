// --------------------------------------------------------------------------
// $453B0 of the B.I.G. digi PLAY: the note through the instrument's octave
// flicker, its envelope (set 1 adds each step to the note, set 2 replaces the
// note with it) and its fall (digi_big_play.zig, digi_big_note.zig).
// Set 2 does not reload its count when it runs out: the 68000's, kept.
// --------------------------------------------------------------------------
const digi = @import("digi.zig");
const At = @import("digi_big_map.zig").At;

pub fn env(comptime Bus: type, at: *const At, v: u32, note: u8) u8 {
    const m = digi.Access(Bus);
    var d0 = note;
    const d3 = m.rd8(at.cnt);
    if (m.btst(v + 0x27, 6) and d3 & 2 != 0) d0 +%= 0x0C; // an octave up every other two frames
    if (!m.btst(v + 0x29, 1) and m.btst(v + 0x27, 7) and count(Bus, v)) {
        m.wr8(v + 0x2B, m.rd8(v + 0x2C));
        const a2 = m.rd32(v + 0x2E);
        if (m.rd8(a2 +% 1) != 0xFF) {
            d0 +%= m.rd8(a2);
            m.wr32(v + 0x2E, a2 +% 1);
        }
    }
    var a2 = m.rd32(v + 0x2E);
    if (m.btst(v + 0x29, 1) and m.btst(v + 0x27, 7)) {
        const due = count(Bus, v);
        d0 = m.rd8(a2);
        if (due and m.rd8(a2 +% 1) != 0xFF) a2 +%= 1;
        m.wr32(v + 0x2E, a2);
    }
    if (m.btst(v + 0x27, 5)) {
        const d4 = m.rd8(v + 0x1D);
        if (d4 != 1) {
            m.wr8(v + 0x1D, d4 -% 1);
            d0 -%= 1;
        }
    }
    return d0;
}

/// subq.b #1,$2B(a0) / cmpi.b #0,$2B(a0): true when the envelope's count runs out.
fn count(comptime Bus: type, v: u32) bool {
    const m = digi.Access(Bus);
    const t = m.rd8(v + 0x2B) -% 1;
    m.wr8(v + 0x2B, t);
    return t == 0;
}
