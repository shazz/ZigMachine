// --------------------------------------------------------------------------
// SysInfo — putting the text grid on the glass through the ROM's GEM context.
// A row is redrawn only across the span where the page changed (grid.diff),
// so a live value costs its own few cells, not the screen. A fresh screen is
// one blitter fill and the page's non-blank text: the glass then holds blanks.
// --------------------------------------------------------------------------
const rom = @import("rom_sdk");
const grid = @import("grid.zig");

pub const SW: i16 = 640;
pub const SH: i16 = 200;
const CELL: i16 = rom.CELL;

/// Paint the paper and record that the glass holds a blank page.
pub fn blank(g: rom.Gui, shown: *grid.Grid) void {
    g.rect(.{ .x = 0, .y = 0, .w = SW, .h = SH }, rom.WHITE);
    shown.clear();
}

/// Draw what changed between `want` and the glass (`shown`), row by row.
pub fn flush(g: rom.Gui, want: *const grid.Grid, shown: *grid.Grid) void {
    for (0..grid.ROWS) |row| {
        const sp = grid.diff(want, shown, row) orelse continue;
        drawSpan(g, want, row, sp);
        grid.commit(want, shown, row, sp);
    }
}

fn drawSpan(g: rom.Gui, want: *const grid.Grid, row: usize, sp: grid.Span) void {
    const y: i16 = @intCast(row * CELL);
    var c = sp.c0;
    while (c < sp.c1) {
        const e = grid.runEnd(want, row, c, sp.c1);
        const x: i16 = @intCast(c * CELL);
        const s = want.ch[row][c..e];
        switch (want.at[row][c]) {
            .plain => g.text(s, x, y, rom.BLACK, rom.WHITE),
            .inverse => g.text(s, x, y, rom.WHITE, rom.BLACK),
            .under => {
                g.text(s, x, y, rom.BLACK, rom.WHITE);
                // under the glyphs' last row, which the 8x8 font leaves blank for capitals
                g.fill(x, y + CELL - 1, @intCast((e - c) * CELL), 1, rom.BLACK);
            },
        }
        c = e;
    }
}
