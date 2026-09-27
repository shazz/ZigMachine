// --------------------------------------------------------------------------
// The enemies' tile collision $3D4C2 (the model's c_enemy.py, literal): the
// attributes of the tiles under the enemy, OR-ed over 3 or 4 rows, plus bit6
// when it stands inside the moving platform (slot 0); the result is masked by
// hit_mask and stored in hit_result.
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const hit = @import("hit.zig");
const world = @import("world.zig");

/// OR the attributes of `nrows` tile rows (3 or 2 columns); the rows above
/// the last are masked with $6F before the last (feet) row.
fn rows(a1_: i64, attr: i64, three: bool, nrows: i64) i64 {
    var a1 = a1_;
    var d0: i64 = 0;
    var d1: i64 = 0;
    var r: i64 = 0;
    while (r < nrows) : (r += 1) {
        if (r == nrows - 1) {
            d0 &= 0x6F;
            d1 &= 0x6F;
        }
        if (three) {
            d0 |= m.rb(attr + m.rb(a1));
            d1 |= m.rb(attr + m.rb(a1 + 1));
            d0 |= m.rb(attr + m.rb(a1 + 2));
        } else {
            d0 |= m.rb(attr + m.rb(a1));
            d0 |= m.rb(attr + m.rb(a1 + 1));
        }
        a1 += 0x20;
    }
    if (three) {
        d0 &= ~@as(i64, 0x82) & 0xFF;
        d0 |= d1;
    }
    return d0;
}

/// $3D4C2(d6 x, d7 y): the attributes under the enemy (+ bit6 inside the
/// platform); hit_result = that & hit_mask; carry = hit_result & $D0.
pub fn tiles(d6_: i64, d7: i64) bool {
    const attr = m.rl(0x39056) & 0xFFFFFF;
    const d6 = (d6_ + 4) & 0xFFFF;
    const col = d6 >> 3;
    const row = (((d7 & 0xFF00) | (d7 & 0xF8)) * 4) & 0xFFFF;
    const a1 = m.idx(m.idx(world.TILEMAP, col), row);
    var d0 = rows(a1, attr, d6 & 7 != 0, if (d7 & 4 != 0) 4 else 3);
    if (m.rw(0x3A184) != 0) {
        const d2 = m.rw(0x3A194);
        const d3 = m.rw(0x3A196);
        const px = hit.rws(0x3A188);
        const py = hit.rws(0x3A18A);
        var d1 = m.s16(d6 - d2);
        if (d1 < px and m.s16(d1 + d2 + 0xF) >= px) {
            d1 = m.s16(d7 - d3);
            if (d1 < py and m.s16(d1 + d3 + 0x14) >= py) d0 |= 0x40;
        }
    }
    d0 &= m.rb(hit.HIT_MASK);
    m.wb(hit.HIT_RESULT, d0);
    return d0 & 0xD0 != 0;
}
