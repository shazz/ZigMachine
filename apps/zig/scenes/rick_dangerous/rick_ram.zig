// --------------------------------------------------------------------------
// Rick's addresses (absolute, as the 68000 code writes them: the model's
// b_ram.py) and the small helpers every part of his handler uses.
// --------------------------------------------------------------------------
const m = @import("ram.zig");

// slot 1 (Rick) at $3A1D0
pub const R_TYPE: i64 = 0x3A1D0;
pub const R_DIR: i64 = 0x3A1D2;
pub const R_X: i64 = 0x3A1D4;
pub const R_Y: i64 = 0x3A1D6;
pub const R_VY: i64 = 0x3A1D8;
pub const R_YFRAC: i64 = 0x3A1DA;
pub const R_YLO: i64 = 0x3A1D7; // the low byte of y
pub const R_HOMEX: i64 = 0x3A1DC; // +$0C: x before this frame's move
pub const R_SPRITE: i64 = 0x3A1F2;
pub const R_ANIM: i64 = 0x3A1FA;
// slot 2 (bullet) at $3A21C, slot 3 (dynamite) at $3A268
pub const B_TYPE: i64 = 0x3A21C;
pub const B_DIR: i64 = 0x3A21E;
pub const B_X: i64 = 0x3A220;
pub const B_Y: i64 = 0x3A222;
pub const B_DIRTY0: i64 = 0x3A232;
pub const B_DIRTY1: i64 = 0x3A238;
pub const B_SPRITE: i64 = 0x3A23E;
pub const D_TYPE: i64 = 0x3A268;
pub const D_X: i64 = 0x3A26C;
pub const D_Y: i64 = 0x3A26E;
pub const D_SPRH: i64 = 0x3A27C;
pub const D_DIRTY0: i64 = 0x3A27E;
pub const D_DIRTY1: i64 = 0x3A284;
pub const D_ANIM: i64 = 0x3A292;
// Rick's variables $3B994..
pub const CRAWL: i64 = 0x3B994;
pub const AIR: i64 = 0x3B995;
pub const LADDER: i64 = 0x3B996;
pub const LATCH: i64 = 0x3B997;
pub const FLAGS: i64 = 0x3B998;
pub const MOVED: i64 = 0x3B999;
pub const DYING: i64 = 0x3B99A;
pub const BLAST_DONE: i64 = 0x3B99C;
pub const POKE_SOUND: i64 = 0x3B99E;
pub const POKE_ON: i64 = 0x3B9A0;
pub const POKE_X: i64 = 0x3B9A2;
pub const POKE_Y: i64 = 0x3B9A4;
pub const BULLET_X: i64 = 0x3B9A6;
pub const BULLET_Y: i64 = 0x3B9A8;
pub const BLAST_ON: i64 = 0x3B9AA;
pub const KILLED: i64 = 0x3B9B0;
pub const ATTR: i64 = 0x3CA8C;
pub const ATTR2: i64 = 0x3CA8D;
pub const CHECKPOINT: i64 = 0x3BA3A;
pub const MAP_ROW: i64 = 0x3904C;
pub const JOY: i64 = 0x38CAD;
pub const BULLETS: i64 = 0x3ADAC;
pub const DYNAMITE: i64 = 0x3ADAE;
pub const LIVES: i64 = 0x3ADB0;
pub const DIRTY_BULLETS: i64 = 0x3ADD4;
pub const DIRTY_DYNAMITE: i64 = 0x3ADD6;
pub const DIRTY_LIVES: i64 = 0x3ADD8;
pub const BONUS_ON: i64 = 0x3B89A;

/// addi.w #$80, vy; cmpi.w #$800, vy; ble; move.w #$800, vy
pub fn vyFall() void {
    m.ww(R_VY, m.rw(R_VY) + 0x80);
    if (m.sw(R_VY) > 0x800) m.ww(R_VY, 0x800);
}

/// move.b y+1, d4; andi.b #$F8; ori.b #low3; move.b d4, y+1
pub fn ySnap(low3: i64) void {
    m.wb(R_YLO, (m.rb(R_YLO) & 0xF8) | low3);
}
