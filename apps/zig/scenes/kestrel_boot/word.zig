// --------------------------------------------------------------------------
// KESTREL BOOT: the wordmark, KESTREL in wide geometric capitals (a 5x7 grid, each cell
// 4 pixels wide and 3 tall: a stretched, "hardware" look), drawn once at init, each
// letter in its own palette entry so marks.zig lights them one by one. Under it,
// "Z I G M A C H I N E" in the system font, in one more entry.
// --------------------------------------------------------------------------
const zg = @import("zigos");

pub const LETTERS: usize = 7;
pub const FIRST: u8 = 16; // palette entries 16..22, one a letter
pub const SUB_INK: u8 = 24;
pub const CELL_W: u16 = 4;
pub const CELL_H: u16 = 3;
const ADVANCE: u16 = 5 * CELL_W + 6;
pub const X: u16 = 200 - (LETTERS * ADVANCE - 6) / 2;
pub const Y: u16 = 168; // physical line of the letters' top (plane 1 is an overscan plane)
const SUB = "Z I G M A C H I N E";
const SUB_Y: i16 = 202;

// One u8 a row, bit 4 = the leftmost column.
const K = [7]u8{ 0b10001, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001 };
const E = [7]u8{ 0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111 };
const S = [7]u8{ 0b01111, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110 };
const T = [7]u8{ 0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100 };
const R = [7]u8{ 0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001 };
const L = [7]u8{ 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111 };
const WORD = [LETTERS]*const [7]u8{ &K, &E, &S, &T, &R, &E, &L };

/// Draws the wordmark and the line under it into plane `fb` (init only).
pub fn paint(os: *zg.ZigOS, fb: *zg.LogicalFB) void {
    for (WORD, 0..) |glyph, i| {
        const x0: i32 = X + @as(i32, @intCast(i)) * ADVANCE;
        for (glyph, 0..) |bits, row| {
            for (0..5) |col| {
                if (bits & (@as(u8, 0x10) >> @intCast(col)) == 0) continue;
                const x = x0 + @as(i32, @intCast(col)) * CELL_W;
                const y: i32 = Y + @as(i32, @intCast(row)) * CELL_H;
                fb.fillRect(x, y, CELL_W, CELL_H, FIRST + @as(u8, @intCast(i)));
            }
        }
    }
    os.printText(fb, SUB, 200 - SUB.len * 4, SUB_Y, SUB_INK, 0);
}
