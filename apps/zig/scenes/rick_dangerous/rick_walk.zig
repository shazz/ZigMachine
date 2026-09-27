// --------------------------------------------------------------------------
// Rick's normal mode, $3BB38-$3BD7E (the model's b_walk.py, literal): walk
// +-2 px, gravity, landing, the bounce tile (attr bit5), the entry into crawl
// mode (attr bit7 + down). walk() returns where the 68000 code continues:
// $3BD80 (after_move) or $3C334 (the tail).
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const R = @import("rick_ram.zig");
const snd = @import("sound.zig");
const collide = @import("rick_tiles.zig").collide;

pub const Next = enum { after, tail };

/// d3 = (ext.l vy << 8) + (y:yfrac), 32-bit (not yet swapped).
fn fixed() i64 {
    const d1 = (m.rw(R.R_Y) << 16) | m.rw(R.R_YFRAC);
    const d3 = (m.s16(m.rw(R.R_VY)) << 8) & 0xFFFFFFFF;
    return (d3 + d1) & 0xFFFFFFFF;
}

pub fn walk(d0: i64) Next {
    if (m.s16(m.rw(R.R_VY)) < 0) m.wb(R.FLAGS, m.rb(R.FLAGS) & (~@as(i64, 0x90) & 0xFF));
    const d3 = fixed();
    const ny = d3 >> 16;
    const nf = d3 & 0xFFFF;
    var d2 = m.rw(R.R_X);
    m.ww(R.R_HOMEX, d2);
    if (d0 & 4 != 0) {
        d2 = (d2 - 2) & 0xFFFF;
        m.wb(R.MOVED, 0xFF);
        m.ww(R.R_DIR, 0xFF);
    } else if (d0 & 8 != 0) {
        d2 = (d2 + 2) & 0xFFFF;
        m.wb(R.MOVED, 0xFF);
        m.ww(R.R_DIR, 0);
    }
    if (!collide(d2, ny)) { // free: move in x and y
        m.ww(R.R_X, d2);
        m.ww(R.R_Y, ny);
        m.ww(R.R_YFRAC, nf);
        R.vyFall();
        return .after;
    }
    const d6 = m.rw(R.R_X);
    if (d2 != d6 and !collide(d6, ny)) { // blocked sideways only: fall in place
        m.ww(R.R_Y, ny);
        m.ww(R.R_YFRAC, nf);
        m.wb(R.MOVED, 0);
        R.vyFall();
        return .after;
    }
    return blocked(d0, d2);
}

/// $3BC2E: the vertical move is blocked.
fn blocked(d0: i64, d2: i64) Next {
    if (m.s16(m.rw(R.R_VY)) < 0) { // head against a ceiling
        m.ww(R.R_YFRAC, 0);
        m.ww(R.R_VY, 0x80);
    } else if (m.rb(R.ATTR) & 0x20 != 0) {
        bounce(d0);
    } else if (crawlEntry(d0)) {
        return .tail;
    } else { // $3BD42: land
        R.ySnap(3);
        m.ww(R.R_YFRAC, 0);
        m.wb(R.AIR, 0xFF);
        m.ww(R.R_VY, 0x100);
    }
    if (!collide(d2, m.rw(R.R_Y))) m.ww(R.R_X, d2); // $3BD6C: the x move alone
    return .after;
}

/// $3BC3A: attr bit5.
fn bounce(d0: i64) void {
    if (m.rw(R.R_VY) == 0x100) {
        m.wb(R.AIR, 0xFF);
        return;
    }
    m.ww(R.R_VY, 0xFE - m.rw(R.R_VY));
    R.ySnap(3);
    m.ww(R.R_YFRAC, 0);
    snd.play(0xF, 1);
    if (d0 & 0x80 == 0 and d0 & 1 != 0) m.ww(R.R_VY, 0xF800);
}

/// $3BCCC: attr bit7, down, no fire, no left/right, x on the grid -> crawl.
fn crawlEntry(d0: i64) bool {
    if (!(m.rb(R.ATTR) & 0x80 != 0 and d0 & 2 != 0 and d0 & 0x80 == 0 and d0 & 0xC == 0)) return false;
    const d4 = m.rw(R.R_X);
    if (d4 & 8 != 0 and d4 & 7 != 0) return false;
    m.ww(R.R_X, (d4 & 0xFF00) | (d4 & 0xF0) | 4);
    R.ySnap(5);
    m.ww(R.R_YFRAC, 0);
    m.wb(R.CRAWL, 0xFF);
    m.wb(R.LADDER, 0);
    m.ww(R.R_ANIM, 0);
    return true;
}
