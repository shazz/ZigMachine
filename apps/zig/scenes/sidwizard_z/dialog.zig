// --------------------------------------------------------------------------
// The text screens (the file dialog) in the repo's own 8x8 system font. The C64 draws them with its
// character ROM ($d018 = $17), which is Commodore's and is not shipped; SID-Wizard's own charset
// (editor_charset.bin) is arranged for the editor's screen codes (its letters are the inverse "bar"
// style, its space is a solid block), so ASCII text from the dialog needs another font. A dialog is
// painted whole when it changes (a key), never every frame.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const dsp = @import("display.zig");

const WIN_X = 40;
const WIN_Y = 36;

/// Clear the plane and write `scr`'s 25 rows of 40 ASCII cells, a run of one colour at a time.
pub fn draw(os: *zg.ZigOS, fb: *zg.LogicalFB, scr: *const dsp.Screen) void {
    fb.clearFrameBuffer(0);
    for (0..200) |y| @memset(fb.fb[(WIN_Y + y) * @as(usize, fb.stride) + WIN_X ..][0..320], dsp.file_bg); // fileBGcolor under the text
    for (0..dsp.ROWS) |r| {
        var c: usize = 0;
        while (c < dsp.COLS) {
            const col = scr.colours[r][c];
            var e = c;
            while (e < dsp.COLS and scr.colours[r][e] == col) e += 1;
            const run = scr.chars[r][c..e];
            if (!allBlank(run)) os.printText(fb, run, @intCast(WIN_X + c * 8), @intCast(WIN_Y + r * 8), col, dsp.file_bg);
            c = e;
        }
    }
}

fn allBlank(run: []const u8) bool {
    for (run) |ch| if (ch != ' ') return false;
    return true;
}
