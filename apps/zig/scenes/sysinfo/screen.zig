// --------------------------------------------------------------------------
// SysInfo — putting the text grid on the glass through the ROM's GEM context.
// A row is redrawn only across the span where the page changed (grid.diff),
// so a live value costs its own few cells, not the screen. A fresh screen is
// one blitter fill and the page's non-blank text: the glass then holds blanks.
//
// Fonts, as HWAM's page has them: the values and labels in the system font
// (the ROM's guiText, 8x8), the program line, the prompt and the headings in
// the SMALL font, drawn by the ROM as a G_TEXT object in the program look
// (objc_draw, TEDINFO font 5): the ROM's own small font, so a KOS ROM built
// with Matt's GEM 5.0 asset set draws them in his, and the repo's ROM in
// ZigOS's 6x6. In the desk mode a cell is 8 x 16: each 8x8 row of glyphs is
// drawn, then doubled downwards in the plane (view.zig says why).
// --------------------------------------------------------------------------
const hw = @import("hardware");
const zg = @import("zigos");
const rom = @import("rom_sdk");
const obj = rom.aes.obj;
const grid = @import("grid.zig");
const view = @import("view.zig");

const CELL: i16 = rom.CELL;

/// Plane 0's buffer for every mode: the desk's 640x480 where the machine has the desk
/// mode (medium and low use its first rows, as notepad/screen.zig), else medium's.
pub fn allocPlane(fb: *zg.LogicalFB) bool {
    if (hw.hwDeskAvailable() != 0) {
        if (fb.setDeskPlane()) |_| {
            fb.leaveDesk();
            return true;
        } else |_| {}
    }
    fb.setMediumPlane();
    return false;
}

/// Paint the paper and record that the glass holds a blank page.
pub fn blank(g: rom.Gui, m: view.Mode, shown: *grid.Grid) void {
    g.rect(.{ .x = 0, .y = 0, .w = view.width(m), .h = view.height(m) }, rom.WHITE);
    shown.clear();
}

/// Draw what changed between `want` and the glass (`shown`), row by row.
pub fn flush(g: rom.Gui, m: view.Mode, want: *const grid.Grid, shown: *grid.Grid) void {
    for (0..grid.ROWS) |row| {
        const d = grid.diff(want, shown, row) orelse continue;
        const sp = grid.widen(want, shown, row, d);
        drawSpan(g, m, want, row, sp);
        grid.commit(want, shown, row, sp);
    }
}

fn drawSpan(g: rom.Gui, m: view.Mode, want: *const grid.Grid, row: usize, sp: grid.Span) void {
    const y = view.cellY(m, row);
    var c = sp.c0;
    while (c < sp.c1) {
        const e = grid.runEnd(want, row, c, sp.c1);
        const x: i16 = @intCast(c * CELL);
        const w: i16 = @intCast((e - c) * CELL);
        const s = want.ch[row][c..e];
        switch (want.at[row][c]) {
            .plain => big(g, m, s, x, y, rom.BLACK, rom.WHITE),
            .inverse => big(g, m, s, x, y, rom.WHITE, rom.BLACK),
            .small => small(g, m, s, x, y, w, false),
            .under => small(g, m, s, x, y, w, true),
        }
        c = e;
    }
}

/// The system font; in the desk, doubled to the 16-row cell.
fn big(g: rom.Gui, m: view.Mode, s: []const u8, x: i16, y: i16, ink: u8, paper: u8) void {
    g.text(s, x, y, ink, paper);
    if (m == .desk) double(x, y, @intCast(s.len * @as(usize, CELL)));
}

/// Each of the 8 pixel rows at y doubled into 16, from the bottom up (row i goes to 2i and
/// 2i + 1, never over a row not yet read). Plane 0's buffer, as the desk shows it (640 a row).
fn double(x: i16, y: i16, w: u16) void {
    const vbase: usize = @intCast(hw.hwVideoBase());
    const base = vbase + @as(*const volatile u32, @ptrFromInt(vbase + hw.REG_FB_BASE)).*;
    const row0 = base + @as(usize, @intCast(y)) * hw.DESK_WIDTH + @as(usize, @intCast(x));
    var i: usize = 8;
    while (i > 0) {
        i -= 1;
        const src: [*]const u8 = @ptrFromInt(row0 + i * hw.DESK_WIDTH);
        for ([2]usize{ 2 * i + 1, 2 * i }) |to| {
            if (to == i) continue;
            const dst: [*]u8 = @ptrFromInt(row0 + to * hw.DESK_WIDTH);
            @memcpy(dst[0..w], src[0..w]);
        }
    }
}

// One G_TEXT in the small font, in the program's memory while the ROM draws it.
var ted: obj.Ted = .{ .text = 0, .tmplt = 0, .valid = 0, .font = 5, .txtlen = 0, .tmplen = 0 };
var tree = [1]obj.Object{.{ .ty = obj.G_TEXT, .flags = obj.LASTOB }};
var text: [grid.COLS + 1]u8 = undefined; // the run, NUL-terminated as a TEDINFO's te_ptext

/// The small font over the cells [x, x + w): the paper first (the glyphs are narrower than
/// the cells), the text from the run's first cell, the heading's rule on the cell's last row.
fn small(g: rom.Gui, m: view.Mode, s: []const u8, x: i16, y: i16, w: i16, under: bool) void {
    const h = view.cellH(m);
    g.rect(.{ .x = x, .y = y, .w = w, .h = h }, rom.WHITE);
    @memcpy(text[0..s.len], s);
    text[s.len] = 0;
    ted.text = obj.addr(&text);
    ted.txtlen = @intCast(s.len + 1);
    ted.color = 0x1180; // black text, replace mode, on white
    tree[0].spec = obj.addr(&ted);
    tree[0].x = x;
    tree[0].y = y;
    tree[0].w = w;
    tree[0].h = h;
    const t = obj.Tree{ .g = g, .objs = &tree };
    t.draw(0, 0, .{ .x = x, .y = y, .w = w, .h = h });
    if (under) g.fill(x, y + h - 1, @intCast(w), 1, rom.BLACK);
}
