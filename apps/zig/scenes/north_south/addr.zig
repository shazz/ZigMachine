// Flat addresses of the battle's variables and of ns.app's tables (the rip's
// TRACE.md documents each one). RAM address = flat + mem.B.

pub const RNG: u32 = 0x1C7FA;
pub const REC_CONFED: u32 = 0x1C888; // the two 4-byte army records: side, infantry, cavalry, cannons
pub const REC_UNION: u32 = 0x1C88C;
pub const CFG_JOYPLAYER: u32 = 0x1C908; // byte: which player owns the port-1 stick
pub const DEMO_TIMER: u32 = 0x1C90A;
pub const BANK_UNION: u32 = 0x1CC98;
pub const BANK_CONFED: u32 = 0x1CC9C;
pub const BG: u32 = 0x1C934; // long: background buffer
pub const LOGICAL: u32 = 0x1CD28; // long: screen being drawn
pub const PHYSICAL: u32 = 0x1CF16; // long: screen shown

pub const OBJ: u32 = 0x1CD32; // 34 x 12 bytes: x, y, frame, state, anim*
pub const AI_SLOT_PTR: u32 = 0x1CECA; // long: AI slot of the unit being updated
pub const SIDE_BASE: u32 = 0x1CECE; // word: 0 (Union) / 12 (Confederates)
pub const BRIDGE_Y: u32 = 0x1CED0; // word: AI crossing line
pub const REC_A: u32 = 0x1CF1A; // long: record pointers (A = side byte 1 = Union)
pub const REC_B: u32 = 0x1CF1E;
pub const ROW_PTR: u32 = 0x1CF22; // long: -> side+$3A / side+$46 row arrays
pub const UNUSED_26: u32 = 0x1CF26;
pub const SHOT_X: u32 = 0x1CF28;
pub const DIR: u32 = 0x1CF2A; // word: +1 / -1
pub const FRAME_PARITY: u32 = 0x1CF2C;
pub const CMD: u32 = 0x1CF2E; // word: the unit command
pub const MUZZLE: u32 = 0x1CF30;
pub const ANIM_CHANGE: u32 = 0x1CF32;
pub const RAIL_OBJ: u32 = 0x1CF34;
pub const FIELD: u32 = 0x1CF36;
pub const BRIDGE_HITS: u32 = 0x1CF38;
pub const DECOR_END: u32 = 0x1CF3A; // 24 + number of decor objects
pub const CF3E: u32 = 0x1CF3E;
pub const CF40: u32 = 0x1CF40;
pub const CF42: u32 = 0x1CF42;
pub const SIDE_A: u32 = 0x1CF44; // 0x66 bytes each
pub const SIDE_B: u32 = 0x1CFAA;
pub const DRAW: u32 = 0x1D010; // bytes: the y-sorted draw list
pub const BANK_CUR: u32 = 0x1D032; // long: sprite bank of the side being updated
pub const ANIM_NEW: u32 = 0x1D036; // long
pub const GRID: u32 = 0x1D03A; // 40 x 50 bytes, index col*50+row

// side struct offsets
pub const S_HUDX: u32 = 0;
pub const S_CPU: u32 = 2;
pub const S_SEL: u32 = 4;
pub const S_SWITCH: u32 = 6;
pub const S_BLAST: u32 = 8;
pub const S_VOLLEY: u32 = 0xA;
pub const S_DIST: u32 = 0xC;
pub const S_SABRE: u32 = 0xE;
pub const S_CAVREF: u32 = 0x10;
pub const S_INFREF: u32 = 0x12;
pub const S_INFACT: u32 = 0x14;
pub const S_CAVACT: u32 = 0x16;
pub const S_CANACT: u32 = 0x18;
pub const S_POWER: u32 = 0x1A;
pub const S_ALIVE: u32 = 0x1C;
pub const S_AMMO: u32 = 0x1E;
pub const S_20: u32 = 0x20;
pub const S_CAVHALT: u32 = 0x22;
pub const S_ENTER: u32 = 0x24;
pub const S_RETREAT: u32 = 0x26;
pub const S_CAVLEAD: u32 = 0x28;
pub const S_CANLEAD: u32 = 0x2A;
pub const S_INFLEAD: u32 = 0x2C;
pub const S_CAVFORM: u32 = 0x2E;
pub const S_INFFORM: u32 = 0x32;
pub const S_BLASTANIM: u32 = 0x36;
pub const S_BULLETS: u32 = 0x3A;
pub const S_SHELLS: u32 = 0x46;
pub const S_AI_CAN: u32 = 0x4C;
pub const S_AI_CAV: u32 = 0x54;
pub const S_AI_INF: u32 = 0x5C;
pub const S_LEVEL: u32 = 0x64;

// ns.app's tables (flat)
pub const T_LANES_A: u32 = 0x1820C;
pub const T_LANES_B: u32 = 0x18216;
pub const T_LINE_A: u32 = 0x18220;
pub const T_LINE_B: u32 = 0x1822C;
pub const T_CAN_A: u32 = 0x18238;
pub const T_CAN_B: u32 = 0x1823E;
pub const T_COLUMN: u32 = 0x18244;
pub const T_DECOR_SENTINEL: u32 = 0x18250;
pub const T_SPARKLE_XY: u32 = 0x189F8;
pub const T_SPARKLE_COL: u32 = 0x18A28;
pub const A_INF: u32 = 0x18A2C;
pub const A_CAV: u32 = 0x18A90;
pub const A_CAN: u32 = 0x18B1C;
pub const A_MARCH: u32 = 0x18A36;
pub const A_FIRE_B: u32 = 0x18A5E;
pub const A_FIRE_A: u32 = 0x18A68;
pub const A_DIE_INF: u32 = 0x18A72;
pub const A_BUMP_INF: u32 = 0x18A7C;
pub const A_CAV_BUMP: u32 = 0x18AAE;
pub const A_CAV_HALT: u32 = 0x18AC2;
pub const A_SABRE: u32 = 0x18ACC;
pub const A_FALL: u32 = 0x18AE0;
pub const A_HORSE: u32 = 0x18AEA;
pub const A_CAN_DIE_BLAST: u32 = 0x18B30;
pub const A_CAN_DIE: u32 = 0x18B3A;
pub const A_BLAST: u32 = 0x18B6C;
pub const T_JOYDIR: u32 = 0x18B94;
pub const AI_SCRIPT_CAN: u32 = 0x17E34;
pub const AI_SCRIPT_INF: u32 = 0x17E38;
pub const AI_SCRIPT_CAV: u32 = 0x17E46;

/// Terrain: (table, first column) for the river and the canyon.
pub const T_TERRAIN = [2][2]u32{ .{ 0x182F2, 11 }, .{ 0x1857C, 15 } };
/// Decor lists: (objects, cells, end) — river variant 1 / 0, canyon, plain variant 1 / 0.
pub const Decor = struct { list: u32, cells: u32, end: i32 };
pub const DECOR_RIVER = [2]Decor{ .{ .list = 0x18874, .cells = 0x18898, .end = 0x1E }, .{ .list = 0x18806, .cells = 0x18830, .end = 0x1F } };
pub const DECOR_CANYON = Decor{ .list = 0x188E0, .cells = 0x18904, .end = 0x1E };
pub const DECOR_PLAIN = [2]Decor{ .{ .list = 0x1899C, .cells = 0x189C0, .end = 0x1E }, .{ .list = 0x1894C, .cells = 0x18970, .end = 0x1E } };

pub inline fn obj(k: i32) u32 {
    return @intCast(@as(i32, OBJ) + 12 * k);
}
