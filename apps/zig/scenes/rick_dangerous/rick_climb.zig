// --------------------------------------------------------------------------
// $3C0FE-$3C262, the mode flagged by $3B994 (rick_crawl): free +-2 px moves
// in x and y with gravity off (vy held at $100): climbing a ladder, crawling
// in a tunnel. Up sets vy = $FE00 (so leaving the mode with it jumps). The
// model's b_climb.py, literal; ends at $3C334.
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const R = @import("rick_ram.zig");
const snd = @import("sound.zig");
const collide = @import("rick_tiles.zig").collide;

pub fn climb(d0: i64) void {
    var d2 = m.rw(R.R_X);
    var d3 = m.rw(R.R_Y);
    const d7 = d3;
    m.ww(R.R_VY, 0x100);
    m.wb(R.FLAGS, m.rb(R.FLAGS) & 0x7F);
    if (d0 & 4 != 0) {
        d2 = (d2 - 2) & 0xFFFF;
        m.ww(R.R_DIR, 0xFF);
        m.wb(R.MOVED, m.rb(R.MOVED) | 1);
    } else if (d0 & 8 != 0) {
        d2 = (d2 + 2) & 0xFFFF;
        m.ww(R.R_DIR, 0);
        m.wb(R.MOVED, m.rb(R.MOVED) | 1);
    }
    if (d0 & 1 != 0) {
        d3 = (d3 - 2) & 0xFFFF;
        m.ww(R.R_VY, 0xFE00);
        m.wb(R.FLAGS, m.rb(R.FLAGS) & 0xEF);
        m.wb(R.MOVED, m.rb(R.MOVED) | 2);
    } else if (d0 & 2 != 0) {
        d3 = (d3 + 2) & 0xFFFF;
        m.wb(R.MOVED, m.rb(R.MOVED) | 2);
    }
    if (m.rb(R.MOVED) & 1 != 0) { // $3C192: the x move
        if (collide(d2, d7) and m.rb(R.ATTR) & 0x40 != 0) {
            m.wb(R.MOVED, m.rb(R.MOVED) & 0xFE);
        } else {
            m.ww(R.R_X, d2);
        }
    }
    if (m.rb(R.MOVED) & 2 != 0 and !collide(m.rw(R.R_X), d3)) return movedY(d3); // $3C1B4
    if (d0 & 2 != 0) { // $3C1CC
        if (m.rb(R.ATTR) & 0x80 != 0) return movedY(d3);
        m.ww(R.R_VY, 0x100); // blocked going down: leave
        m.wb(R.CRAWL, 0);
        m.wb(R.MOVED, 0);
        m.ww(R.R_ANIM, 0);
        m.ww(R.R_YFRAC, 0);
        return;
    }
    m.ww(R.R_VY, 0x100); // $3C200
    m.wb(R.MOVED, m.rb(R.MOVED) & 0xFD);
    if (m.rb(R.MOVED) & 1 != 0) checkLeave();
}

/// $3C21E.
fn movedY(d3: i64) void {
    m.ww(R.R_Y, d3);
    checkLeave();
}

/// $3C224: off the ladder / tunnel tiles (attr bit1 clear): back to normal.
fn checkLeave() void {
    if (m.rb(R.ATTR) & 2 != 0) return;
    m.wb(R.CRAWL, 0);
    m.ww(R.R_ANIM, 0);
    m.ww(R.R_YFRAC, 0);
    if (m.rw(R.R_VY) != 0x100) snd.play(0xE, 1);
}
