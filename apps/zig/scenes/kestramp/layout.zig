// --------------------------------------------------------------------------
// KESTRAMP: the window's geometry and palette indices, in one place. 320 x 200,
// one plane; coordinates are logical (the page draws each column twice wide).
// --------------------------------------------------------------------------
pub const PLANE = 0;
pub const BG: u8 = 0;
pub const INK: u8 = 1;
pub const BEVEL_LIGHT: u8 = 4;
pub const BEVEL_DARK: u8 = 5;
pub const FACE: u8 = 6;
pub const GOLD: u8 = 7;
pub const DIM: u8 = 8;
pub const LIT_FACE: u8 = 11;
pub const TRACK_BG: u8 = 12;

pub const BTN_Y: i32 = 54;
pub const BTN_H: usize = 17;
pub const BTN_W: usize = 48;
pub const BTN_STRIDE: i32 = 50;
pub const TOG_Y: i32 = 76;
pub const TOG_H: usize = 11;
pub const TOG_W: usize = 74;
pub const TOG_X: [2]i32 = .{ 6, 86 };
pub const BAR_X: i32 = 6;
pub const BAR_Y: i32 = 44;
pub const BAR_W: usize = 306;
pub const BAR_H: usize = 5;
pub const STATUS_Y: i32 = 90;
pub const LIST_X: i32 = 6;
pub const LIST_Y: i32 = 102;
pub const LIST_W: usize = 306;
pub const ROW_H: usize = 9;
pub const ROWS: usize = 8;
pub const LIST_H: usize = ROW_H * ROWS;

pub fn btnX(i: usize) i32 {
    return 6 + @as(i32, @intCast(i)) * BTN_STRIDE;
}
