// --------------------------------------------------------------------------
// $3BD80-$3C0FA, after the normal-mode move (the model's b_act.py, literal):
// ladders (attr bit1), the jump, and the fire combinations: poke left/right,
// shoot up, dynamite down. Every path ends at $3C334 (the tail).
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const R = @import("rick_ram.zig");
const snd = @import("sound.zig");

/// $3BD80.
pub fn afterMove(d0: i64) void {
    if (m.rb(R.ATTR) & 2 != 0) {
        if (d0 & 0x80 != 0 and m.rb(R.AIR) != 0) return stand(d0);
        if (m.rb(R.LADDER) == 0) {
            if (d0 & 1 != 0 or (d0 & 2 != 0 and m.rb(R.AIR) == 0)) { // $3BDC0: onto the ladder
                m.wb(R.CRAWL, 0xFF);
                m.ww(R.R_VY, 0x100);
                m.ww(R.R_YFRAC, 0);
                m.ww(R.R_ANIM, 0);
            } else if (d0 & 2 != 0) { // $3BDE0
                m.wb(R.LADDER, 0xFF);
                m.ww(R.R_ANIM, 0);
            } else {
                m.wb(R.CRAWL, 0);
            }
            return;
        }
    }
    if (m.rb(R.AIR) != 0) return stand(d0); // $3BDF2
    if (m.rb(R.ATTR2) == 0) m.wb(R.LADDER, 0);
}

/// $3BE0E: on the ground.
fn stand(d0: i64) void {
    if (d0 & 0x80 != 0) return fire(d0);
    m.ww(R.POKE_SOUND, 0);
    const d4: i64 = if ((d0 & 2) | m.rb(R.ATTR2) != 0) 0xFF else 0;
    if (d4 != m.rb(R.LADDER)) {
        m.wb(R.LADDER, d4);
        m.ww(R.R_ANIM, 0);
    }
    if (m.rb(R.LADDER) != 0) {
        m.wb(R.AIR, 0);
    } else if (d0 & 1 != 0) { // jump
        m.ww(R.R_VY, 0xFA80);
        snd.play(0xE, 1);
    }
}

/// $3BE76.
fn fire(d0: i64) void {
    if (m.rb(R.LADDER) != 0 and m.rb(R.ATTR2) != 0) return;
    if (d0 & 4 != 0) return poke(0xFF, 0);
    if (d0 & 8 != 0) return poke(0, 0x17);
    m.ww(R.POKE_SOUND, 0);
    if (d0 & 1 != 0) return shoot();
    if (d0 & 2 != 0) dynamite();
}

fn poke(face: i64, dx: i64) void {
    m.ww(R.POKE_ON, 0xFF);
    m.ww(R.R_DIR, face);
    m.ww(R.R_X, m.rw(R.R_HOMEX));
    m.wb(R.LADDER, 0);
    m.ww(R.POKE_Y, m.rw(R.R_Y) + 0xE);
    m.ww(R.POKE_X, m.rw(R.R_X) + dx);
    if (m.rw(R.POKE_SOUND) != 0) return;
    m.ww(R.POKE_SOUND, 0xFF);
    snd.play(0xB, 1);
}

/// $3BF5E: needs the fire latch released, room ahead, no bullet out, ammo.
fn shoot() void {
    if (m.rb(R.LATCH) != 0) return;
    m.wb(R.LATCH, 0xFF);
    const d4 = m.rw(R.R_HOMEX);
    m.ww(R.R_X, d4);
    m.wb(R.LADDER, 0);
    if (m.rw(R.R_DIR) != 0) {
        if (m.s16(d4) <= 8) return;
    } else if (m.s16(d4) >= 0xE0) return;
    if (m.rw(R.B_TYPE) != 0) return;
    if (m.rb(R.BULLETS) == 0) {
        snd.play(9, 1);
        return;
    }
    m.wb(R.BULLETS, m.rb(R.BULLETS) - 1);
    m.wb(R.DIRTY_BULLETS, 0xFF);
    m.ww(R.B_TYPE, 2);
    snd.play(8, 1);
    snd.play(8, 0);
    launch();
}

/// The bullet's slot: its dirty rects, direction, position and sprite from Rick's.
fn launch() void {
    m.wb(R.B_DIRTY0, m.rb(R.B_DIRTY0) & 0xFE);
    m.wb(R.B_DIRTY1, m.rb(R.B_DIRTY1) & 0xFE);
    m.ww(R.B_DIR, m.rw(R.R_DIR));
    var d4 = (m.rw(R.R_Y) + 7) & 0xFFFF;
    m.ww(R.B_Y, d4);
    m.ww(R.BULLET_Y, d4 + 4);
    d4 = m.rw(R.R_X);
    if (m.rw(R.B_DIR) != 0) {
        d4 = (d4 - 1) & 0xFFFF;
        m.ww(R.B_X, d4);
        m.ww(R.BULLET_X, d4);
        m.wl(R.B_SPRITE, 0x1E470);
    } else {
        d4 = (d4 + 1) & 0xFFFF;
        m.ww(R.B_X, d4);
        m.ww(R.BULLET_X, d4 + 0x17);
        m.wl(R.B_SPRITE, 0x1E320);
    }
}

/// $3C07E.
fn dynamite() void {
    if (m.rw(R.D_TYPE) != 0 or m.rb(R.DYNAMITE) == 0) return;
    m.wb(R.DYNAMITE, m.rb(R.DYNAMITE) - 1);
    m.wb(R.DIRTY_DYNAMITE, 0xFF);
    m.ww(R.D_TYPE, 3);
    m.wb(R.D_DIRTY0, m.rb(R.D_DIRTY0) & 0xFE);
    m.wb(R.D_DIRTY1, m.rb(R.D_DIRTY1) & 0xFE);
    m.ww(R.D_SPRH, 0x10);
    var d4 = (m.rw(R.R_X) + 4) & 0xFFFF;
    if (m.s16(d4) > 0xE8) d4 = 0xE8;
    m.ww(R.D_X, d4);
    m.ww(R.D_Y, m.rw(R.R_Y) + 5);
    m.ww(R.D_ANIM, 0);
}
