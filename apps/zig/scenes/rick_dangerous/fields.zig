// --------------------------------------------------------------------------
// Names for the game's RAM (absolute addresses), the reference model's
// fields.py. Slot fields are offsets inside a $4C-byte entity slot.
// --------------------------------------------------------------------------

// the 13 entity slots ($FFFF-terminated)
pub const ENT: i64 = 0x3A184;
pub const ENT_SZ: i64 = 0x4C;
pub const SCREENS = [2]i64{ 0x70000, 0x78000 };

// sound driver
pub const DIGI_NEXT: i64 = 0x34A7E;
pub const DIGI_TACR: i64 = 0x34A82;
pub const DIGI_TADR: i64 = 0x34A83;
pub const SND_MODE: i64 = 0x34A84;
pub const SFX_ALT: i64 = 0x34A85;
pub const SND_LOOP: i64 = 0x34A86;
pub const SND_ID: i64 = 0x34A87;
pub const MUSIC_BUSY: i64 = 0x34B18;
pub const DIGI_PTR: i64 = 0x3524A;

// I/O + VBL
pub const JOY0: i64 = 0x38CAC;
pub const JOY: i64 = 0x38CAD;
pub const KEY: i64 = 0x38CAE;
pub const ACIA_HDR_FE: i64 = 0x38D68;
pub const ACIA_HDR_FF: i64 = 0x38D6A;
pub const SCREEN_PTR: i64 = 0x38D6C;
pub const VBL_COUNT: i64 = 0x38DB6;

// RNG, world
pub const RNG_A: i64 = 0x39042;
pub const RNG_B: i64 = 0x39046;
pub const SPAWN_ROWS: i64 = 0x3904A;
pub const MAP_ROW: i64 = 0x3904C;
pub const MAP_PTR: i64 = 0x3904E;
pub const TILE_BANK: i64 = 0x39052;
pub const TILE_ATTR: i64 = 0x39056;
pub const SUBMAP: i64 = 0x3905A;
pub const SPAWN_LIST: i64 = 0x3905E;
pub const SEL_LEVEL: i64 = 0x39342;
pub const MAX_LEVEL: i64 = 0x39344;
pub const LEVEL_SELECT_ON: i64 = 0x39346;
pub const DRAW_TMP: i64 = 0x3980C;
pub const TILEMAP: i64 = 0x39C00;
pub const SCROLL_ON: i64 = 0x3A180;
pub const SCROLL_DY: i64 = 0x3A182;

// HUD / score
pub const SCORE_BCD: i64 = 0x3ADA8;
pub const BULLETS: i64 = 0x3ADAC;
pub const DYNAMITE: i64 = 0x3ADAE;
pub const LIVES: i64 = 0x3ADB0;
pub const SCORE_TEXT: i64 = 0x3ADB2;
pub const DIRTY_SCORE: i64 = 0x3ADD2;
pub const DIRTY_BULLETS: i64 = 0x3ADD4;
pub const DIRTY_DYNAMITE: i64 = 0x3ADD6;
pub const DIRTY_LIVES: i64 = 0x3ADD8;
pub const LEVEL: i64 = 0x3B008;
pub const LEVELS: i64 = 0x3AFA4;

// timed bonus
pub const BONUS_ON: i64 = 0x3B89A;
pub const BONUS_TICK: i64 = 0x3B89C;
pub const BONUS_VALUE: i64 = 0x3B89E;

// Rick
pub const RICK_DYING: i64 = 0x3B99A;
pub const GAME_COMPLETE: i64 = 0x3D8BE;
pub const LIVE_PAL: i64 = 0x3D974;

// slot 1 = Rick
pub const R_TYPE: i64 = 0x3A1D0;
pub const R_X: i64 = 0x3A1D4;
pub const R_Y: i64 = 0x3A1D6;
