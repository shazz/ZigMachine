// --------------------------------------------------------------------------
// frame.zig — the C64 picture as colour indices: 400x280 C64 pixels (the
// 320x200 text window at (40,36) plus the border around it, the same crop as
// ../sidwizard_re/shots/*.png after halving their doubled width).
//
// Layers, back to front: black border/background, the 25 text rows
// (editor_charset.bin + colour RAM), the 26th row (display lines 1..7 at
// y=237..243 between two colour-15 raster bars, the `$d011=$1f` trick in
// irq.inc), then the border sprites (upper logo/readouts, lower orderlist).
// --------------------------------------------------------------------------
const dsp = @import("display.zig");
const border = @import("border.zig");

pub const W = 400;
pub const H = 280;
const win_x = 40; // text window origin
const win_y = 36;
const row26_y = win_y + 200; // the bar line; glyph lines 1..7 follow
/// Pseudo colours 16/17: the reference shot shows the sprite colour (12) and
/// the colour-15 raster bars as the average of two palette entries
/// ((137+189)/2 = 162 and (189+255)/2 = 222), so they are kept as measured.
pub const bar_col: u8 = 17;
pub const sprite_col: u8 = 16;

pub const charset = @embedFile("editor_charset.bin"); // VICE dump of $d000..$d7ff

pub const Frame = struct {
    px: [H][W]u8 = [_][W]u8{[_]u8{0} ** W} ** H,
};

fn glyphRow(f: *Frame, x: usize, y: usize, bits: u8, col: u8) void {
    for (0..8) |i| {
        if (bits & (@as(u8, 0x80) >> @intCast(i)) != 0) f.px[y][x + i] = col;
    }
}

fn textRows(f: *Frame, scr: *const dsp.Screen) void {
    for (0..dsp.ROWS) |r| for (0..dsp.COLS) |c| {
        const code: usize = scr.chars[r][c];
        for (0..8) |l| {
            glyphRow(f, win_x + c * 8, win_y + r * 8 + l, charset[code * 8 + l], scr.colours[r][c]);
        }
    };
}

fn bar(f: *Frame, y: usize) void {
    for (win_x..win_x + 320) |x| f.px[y][x] = bar_col;
}

/// The 26th row: `row26` chars, glyph lines 1..7, in the pattern-fx colour.
fn row26(f: *Frame, over: *const dsp.Overlay, col: u8) void {
    bar(f, row26_y);
    for (0..dsp.COLS) |c| {
        const code: usize = over.row26[c];
        for (1..8) |l| {
            glyphRow(f, win_x + c * 8, row26_y + l, charset[code * 8 + l], col);
        }
    }
    bar(f, row26_y + 8);
}

/// 7 sprites, 24x21 expanded in X, 48 C64 pixels apart. `ghost`: the low
/// border sprites sit behind the VIC idle graphics (`$3fff` = %10000001,
/// settings.cfg GHOSTPIXEL_ON), which blanks columns 0 and 7 of every 8-pixel
/// cell and so separates the two chars of an orderlist pair.
fn sprites(f: *Frame, data: []const u8, y0: usize, ghost: bool) void {
    for (0..7) |k| for (0..21) |ln| for (0..3) |bi| {
        const b = data[k * 64 + ln * 3 + bi];
        for (0..8) |bit| {
            if (b & (@as(u8, 0x80) >> @intCast(bit)) == 0) continue;
            const x = win_x + k * 48 + (bi * 8 + bit) * 2;
            for (0..2) |d| {
                const m = (x + d - win_x) % 8;
                if (!ghost or (m != 0 and m != 7)) f.px[y0 + ln][x + d] = sprite_col;
            }
        }
    };
}

/// compose: `editor` selects the raster-trick screen (26th row + sprites);
/// the file dialog and the start-up menu are plain 25-row text screens.
pub fn compose(f: *Frame, scr: *const dsp.Screen, over: ?*const dsp.Overlay, b: ?*const border.Border) void {
    f.* = .{};
    textRows(f, scr);
    if (over) |o| row26(f, o, 12);
    if (b) |bb| {
        sprites(f, bb.up[0x40..], 14, false);
        sprites(f, &bb.low, 246, true);
    }
}
