// --------------------------------------------------------------------------
// Rick's death $3C266, the death fall $3C2C8, and the animation frame choice
// $3C334-$3C4D6 (tables $36618..$3666F): the model's b_anim.py, literal.
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const R = @import("rick_ram.zig");
const snd = @import("sound.zig");

const RIGHT_TO_LEFT: i64 = 0xFC0; // the left-facing frames follow the right-facing ones

/// $3C266: lives - 1, scream (digi $13), vy = $FD00, drift 3 px a frame.
pub fn die() void {
    m.wb(R.DYING, 0xFF);
    m.wb(R.LIVES, m.rb(R.LIVES) - 1);
    m.wb(R.DIRTY_LIVES, 0xFF);
    m.ww(R.BONUS_ON, 0);
    snd.play(0x13, 1);
    m.ww(R.R_YFRAC, 0);
    m.ww(R.R_ANIM, 0);
    m.ww(R.R_VY, 0xFD00);
    m.ww(R.R_DIR, 3);
    if (m.sw(R.R_X) >= 0x80) m.ww(R.R_DIR, -3);
}

/// $3C2C8: x += dir (bouncing off x <= 0 / >= $E8), y:yfrac += vy << 8, vy += $80.
pub fn dyingFall() void {
    const d1 = (m.rw(R.R_Y) << 16) | m.rw(R.R_YFRAC);
    const d3 = (((m.s16(m.rw(R.R_VY)) << 8) & 0xFFFFFFFF) + d1) & 0xFFFFFFFF;
    const d2 = (m.rw(R.R_X) + m.rw(R.R_DIR)) & 0xFFFF;
    const ok = if (m.sw(R.R_DIR) > 0) m.s16(d2) < 0xE8 else m.s16(d2) > 0;
    if (ok) m.ww(R.R_X, d2) else m.ww(R.R_DIR, -m.rw(R.R_DIR));
    m.ww(R.R_YFRAC, d3);
    m.ww(R.R_Y, d3 >> 16);
    m.ww(R.R_VY, m.rw(R.R_VY) + 0x80);
}

/// lea table,a0; bclr #0,d4; add.w d4,d4; move.l (a0,d4.w),sprite
fn frame(table: i64, n: i64) void {
    m.wl(R.R_SPRITE, m.rl(table + m.s16(((n & 0xFFFE) * 2) & 0xFFFF)));
}

/// anim_i + 1 while moving (wrapping at `wrap`, with a sound at the wrap).
fn step(wrap: i64, sound: i64) i64 {
    var d4 = m.rw(R.R_ANIM);
    if (m.rb(R.MOVED) != 0) {
        d4 = (d4 + 1) & 0xFFFF;
        if (m.s16(d4) >= wrap) {
            d4 = 0;
            snd.play(sound, 1);
        }
    }
    m.ww(R.R_ANIM, d4);
    return d4;
}

/// $3C334: the deadly tile (attr bit2), then the frame.
pub fn tail() void {
    if (m.rb(R.ATTR) & 4 != 0) {
        die();
        return deadFrame();
    }
    if (m.rb(R.DYING) != 0) return deadFrame();
    if (!aliveFrame() and m.rw(R.R_DIR) != 0) m.wl(R.R_SPRITE, m.rl(R.R_SPRITE) + RIGHT_TO_LEFT);
}

/// $3C34C.
pub fn deadFrame() void {
    var d4 = (m.rw(R.R_ANIM) + 1) & 0xFFFF;
    if (m.s16(d4) >= 4) d4 = 0;
    m.ww(R.R_ANIM, d4);
    frame(0x36668, d4);
}

/// $3C37C; true when the frame has no left-facing variant (the crawl).
fn aliveFrame() bool {
    if (m.rb(R.LATCH) != 0) {
        m.wl(R.R_SPRITE, m.rl(0x36634));
    } else if (m.rw(R.POKE_ON) != 0) {
        m.wl(R.R_SPRITE, m.rl(0x3663C));
    } else if (m.rb(R.LADDER) != 0) {
        frame(0x3665C, step(4, 0xD));
    } else if (m.rb(R.CRAWL) != 0) {
        frame(0x36620, step(4, 0xC));
        return true;
    } else if (m.rb(R.AIR) != 0) {
        groundFrame();
    } else {
        m.wl(R.R_SPRITE, m.rl(0x3662C));
    }
    return false;
}

/// $3C450: walking (10-step cycle, footstep at 0 and 5) or standing.
fn groundFrame() void {
    if (m.rb(R.MOVED) == 0) {
        m.wl(R.R_SPRITE, m.rl(0x36618));
        return;
    }
    var d4 = (m.rw(R.R_ANIM) + 1) & 0xFFFF;
    if (m.s16(d4) >= 10) d4 = 0;
    m.ww(R.R_ANIM, d4);
    if (d4 == 0 or d4 == 5) snd.play(0xC, 1);
    frame(0x36644, d4);
}
