// --------------------------------------------------------------------------
// Rick (the model's pkg_b.py, literal): the type-1 handler $3BAC8 (walk,
// jump, gravity, ladders, crawl, poke, shoot, dynamite, death, the frame),
// the checkpoint restore (call 5), Rick's flag (call 16) and his reset.
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const R = @import("rick_ram.zig");
const walk = @import("rick_walk.zig");
const act = @import("rick_act.zig");
const climb = @import("rick_climb.zig");
const anim = @import("rick_anim.zig");

/// Call 16, $3BA30: slot 1 type = 1 (Rick again, after $3A698).
pub fn flag() void {
    m.ww(R.R_TYPE, 1);
}

/// $3B9B2: Rick's flags off, vy = $100, 6 bullets, 6 dynamite (HUD dirty).
pub fn reset() void {
    m.ww(R.KILLED, 0);
    for ([_]i64{ R.DYING, R.CRAWL, R.AIR, R.LADDER, R.LATCH, R.ATTR2 }) |a| m.wb(a, 0);
    m.ww(R.R_VY, 0x100);
    m.wb(R.R_YFRAC, 0); // clr.b: the high byte of yfrac only
    m.ww(R.R_DIR, 0);
    m.ww(R.R_ANIM, 0);
    for ([_]i64{ R.POKE_ON, R.BLAST_DONE, R.BLAST_ON, R.POKE_SOUND }) |a| m.ww(a, 0);
    m.wb(R.BULLETS, 6);
    m.wb(R.DYNAMITE, 6);
    m.wb(R.DIRTY_BULLETS, 0xFF);
    m.wb(R.DIRTY_DYNAMITE, 0xFF);
}

/// Call 5, $3BA82: reset, then x, y, dir, map_row, attr2, ladder from the
/// checkpoint $3BA3A, then $3BA30. (The loop's move.b #7,$3904A follows.)
pub fn restoreCheckpoint() void {
    reset();
    m.ww(R.R_X, m.rw(R.CHECKPOINT));
    m.ww(R.R_Y, m.rw(R.CHECKPOINT + 2));
    m.ww(R.R_DIR, m.rw(R.CHECKPOINT + 4));
    m.ww(R.MAP_ROW, m.rw(R.CHECKPOINT + 6));
    m.wb(R.ATTR2, m.rb(R.CHECKPOINT + 8));
    m.wb(R.LADDER, m.rb(R.CHECKPOINT + 9));
    flag();
}

/// Type 1, $3BAC8: the whole of Rick for one frame. The code addresses slot
/// 1 absolutely, whatever the slot it is called for.
pub fn handler() void {
    if (m.rw(R.D_TYPE) == 0) { // no dynamite out: the blast is over
        m.ww(R.BLAST_DONE, 0);
        m.ww(R.BLAST_ON, 0);
    }
    if (m.rb(R.DYING) != 0) {
        anim.dyingFall();
        return anim.deadFrame();
    }
    if (m.rw(R.KILLED) != 0) { // killed by an entity (set by the actors)
        anim.die();
        return anim.deadFrame();
    }
    m.wb(R.AIR, 0);
    m.wb(R.FLAGS, 0xFF);
    m.wb(R.MOVED, 0);
    m.ww(R.POKE_ON, 0);
    const d0 = m.rb(R.JOY);
    if (d0 & 0x81 != 0x81) m.wb(R.LATCH, 0); // fire+up released: the next shot is allowed
    if (m.rb(R.CRAWL) != 0) {
        climb.climb(d0);
    } else if (walk.walk(d0) == .after) {
        act.afterMove(d0);
    }
    anim.tail();
}
