// --------------------------------------------------------------------------
// $3C7F2, Rick against the tile map and the slot-0 platform (the model's
// b_tiles.py, literal). collide(d6 = x, d7 = y) writes rick_attr2 ($3CA8D:
// cleared, then the ladder-top bit6) and rick_attr ($3CA8C: the OR of the
// tile attributes under Rick, masked by rick_flags $3B998); returns the
// carry: attr & $D0. The caller's d6/d7 are unchanged (movem).
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const R = @import("rick_ram.zig");

const TILEMAP: i64 = 0x39C00;
const S0_TYPE: i64 = 0x3A184;
const S0_X: i64 = 0x3A188;
const S0_Y: i64 = 0x3A18A;
const S0_W: i64 = 0x3A194;
const S0_H: i64 = 0x3A196;

/// The attribute accumulators d0 (outer columns) / d1 (middle) and a1.
const Rows = struct {
    a1: i64,
    three: bool,
    attr: i64,
    d0: i64 = 0,
    d1: i64 = 0,

    fn a(self: *const Rows, off: i64) i64 {
        return m.rb((self.attr + m.rb((self.a1 + off) & 0xFFFFFF)) & 0xFFFFFF);
    }

    fn row(self: *Rows) void {
        if (self.three) {
            self.d0 |= self.a(0);
            self.d1 |= self.a(1);
            self.d0 |= self.a(2);
        } else {
            self.d0 |= self.a(0);
            self.d0 |= self.a(1);
        }
        self.a1 += 32;
    }

    fn ladderCheck(self: *Rows) void {
        if (m.rb(R.LADDER) == 0) return;
        m.wb(R.ATTR2, (self.d0 | self.d1) & 0x40);
        self.d0 &= ~@as(i64, 0x44) & 0xFF;
        if (self.three) self.d1 &= ~@as(i64, 0x44) & 0xFF;
    }

    fn mask(self: *Rows) void {
        self.d0 &= 0x6F;
        if (self.three) self.d1 &= 0x6F;
    }
};

pub fn collide(d6_: i64, d7_: i64) bool {
    m.wb(R.ATTR2, 0);
    const d6 = (d6_ + 4) & 0xFFFF;
    const d7 = d7_ & 0xFFFF;
    const d2 = d6 >> 3;
    const d3 = (((d7 & 0xFF00) | (d7 & 0xF8)) * 4) & 0xFFFF;
    var r = Rows{ .a1 = TILEMAP + m.s16(d2) + m.s16(d3), .three = d6 & 7 != 0, .attr = m.rl(0x39056) };
    r.row();
    r.ladderCheck();
    r.row();
    if (d7 & 4 != 0) r.row(); // 4 tile rows
    r.mask();
    r.row();
    var d0 = r.d0;
    if (r.three) d0 = (d0 & (~@as(i64, 0x82) & 0xFF)) | r.d1;
    d0 = platform(d6, d7, d0);
    d0 &= m.rb(R.FLAGS);
    m.wb(R.ATTR, d0);
    return d0 & 0xD0 != 0;
}

/// $3C9F4: slot 0 (the moving platform) counts as a floor tile (bit6).
fn platform(d6: i64, d7: i64, d0: i64) i64 {
    if (m.rw(S0_TYPE) == 0) return d0;
    const w = m.rw(S0_W);
    const h = m.rw(S0_H);
    const x0 = m.sw(S0_X);
    const y0 = m.sw(S0_Y);
    var d1 = (d6 - w) & 0xFFFF;
    if (m.s16(d1) >= x0) return d0;
    d1 = (d1 + w + 0xF) & 0xFFFF;
    if (m.s16(d1) < x0) return d0;
    d1 = (d7 - h) & 0xFFFF;
    if (m.s16(d1) >= y0) return d0;
    d1 = (d1 + h + 0x14) & 0xFFFF;
    if (m.s16(d1) < y0) return d0;
    if (m.rb(R.LADDER) != 0) {
        d1 = (m.rw(S0_Y) + h - 8) & 0xFFFF;
        if (m.s16(d7) > m.s16(d1)) {
            m.wb(R.ATTR2, m.rb(R.ATTR2) | 0x40);
            return d0;
        }
    }
    return d0 | 0x40;
}
