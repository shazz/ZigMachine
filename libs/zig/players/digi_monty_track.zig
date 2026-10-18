// --------------------------------------------------------------------------
// Monty's command $87 ($9FE): the pattern has ended, the voice's track gives
// the next. A track is pattern numbers, with `$80 x` setting the voice's
// transpose to x on the way and `$FF` going back to the start (where no `$80`
// is looked for). Returns the new pattern's first byte, for the row reader.
// --------------------------------------------------------------------------
const digi = @import("digi.zig");
const at = @import("digi_monty_map.zig");
const V = at.V;

pub fn next(comptime Bus: type, b: u32, v: u32) u32 {
    const m = digi.Access(Bus);
    while (true) {
        var pos = m.rd32(v + V.TRACK_POS);
        var t = m.rd32(v + V.TRACK) +% pos;
        pos +%= 1;
        if (m.rd8(t) == 0x80) {
            m.wr8(v + V.SHIFT + 1, m.rd8(t +% 1));
            m.wr32(v + V.TRACK_POS, m.rd32(v + V.TRACK_POS) +% 2);
            continue;
        }
        if (m.rd8(t) == 0xFF) {
            t = m.rd32(v + V.TRACK);
            pos = 1;
        }
        m.wr32(v + V.TRACK_POS, pos);
        const n = @as(u32, m.rd8(t)) << 2;
        return m.rd32(m.rd32(b + at.PATTERNS) +% n);
    }
}
