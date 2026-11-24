// --------------------------------------------------------------------------
// The C64 picture on ONE overscan plane (400x280 indices, planes are the board's main cost), drawn
// incrementally: the library renders the editor's Screen (25x40 cells), the hidden 26th row and the
// border sprites' bytes; this keeps a shadow of each and stores only what changed — a glyph cell, a
// sprite byte, the cursor's box. frame.compose is the full-frame reference (video_test.zig: a
// full repaint equals it, and so does any sequence of incremental ones).
// Integer only. Geometry as frame.zig: the 320x200 window at (40,36); the 26th row's glyph lines 1..7 at
// y=237 between two raster bars; the header sprites at y=14, the orderlist sprites at y=246.
// --------------------------------------------------------------------------
const std = @import("std");
const dsp = @import("display.zig");
const border = @import("border.zig");
const frame = @import("frame.zig");

pub const W = frame.W;
pub const H = frame.H;
const WIN_X = 40;
const WIN_Y = 36;
const ROW26_Y = WIN_Y + 200;
const UP_Y = 14;
const LOW_Y = 246;
const CURSOR_BOX = [9]u16{ 0x1FF, 0x101, 0x101, 0x101, 0x101, 0x101, 0x101, 0x101, 0x1FF }; // bit 8 = left column

pub const Shadow = struct {
    scr: dsp.Screen = undefined,
    row26: [dsp.COLS]u8 = undefined,
    row26_on: bool = false,
    up: [0x240]u8 = undefined,
    low: [0x1c0]u8 = undefined,
    cursor: ?Cursor = null,
    drawn: bool = false, // false: nothing on the plane yet (everything is "changed")
    editor: bool = false, // the last picture had the 26th row and the sprites

    /// Forget what is on the plane: the next `present` repaints everything.
    pub fn invalidate(self: *Shadow) void {
        self.drawn = false;
    }
};

pub const Cursor = struct { x: u16, y: u16, wide: bool, col: u8 };

fn put(px: []u8, x: usize, y: usize, v: u8) void {
    if (x < W and y < H) px[y * W + x] = v;
}

fn cell(px: []u8, r: usize, c: usize, code: u8, col: u8) void {
    for (0..8) |l| {
        const bits = frame.charset[@as(usize, code) * 8 + l];
        for (0..8) |i| px[(WIN_Y + r * 8 + l) * W + WIN_X + c * 8 + i] = if (bits & (@as(u8, 0x80) >> @intCast(i)) != 0) col else 0;
    }
}

fn row26Cell(px: []u8, c: usize, code: u8) void {
    for (1..8) |l| {
        const bits = frame.charset[@as(usize, code) * 8 + l];
        for (0..8) |i| px[(ROW26_Y + l) * W + WIN_X + c * 8 + i] = if (bits & (@as(u8, 0x80) >> @intCast(i)) != 0) 12 else 0;
    }
}

fn bars(px: []u8, v: u8) void {
    for (WIN_X..WIN_X + 320) |x| {
        px[ROW26_Y * W + x] = v;
        px[(ROW26_Y + 8) * W + x] = v;
    }
}

/// One byte (8 sprite bits) of sprite `k` line `ln`, X-expanded: 16 pixels from the byte's place.
fn spriteByte(px: []u8, k: usize, ln: usize, bi: usize, y0: usize, bits: u8, ghost: bool) void {
    for (0..8) |bit| {
        const on = bits & (@as(u8, 0x80) >> @intCast(bit)) != 0;
        for (0..2) |d| {
            const x = WIN_X + k * 48 + (bi * 8 + bit) * 2 + d;
            const blank = ghost and ((x - WIN_X) % 8 == 0 or (x - WIN_X) % 8 == 7);
            put(px, x, y0 + ln, if (on and !blank) frame.sprite_col else 0);
        }
    }
}

fn sprites(px: []u8, data: []const u8, old: ?[]const u8, y0: usize, ghost: bool) void {
    for (0..7) |k| for (0..21) |ln| for (0..3) |bi| {
        const i = k * 64 + ln * 3 + bi;
        if (old != null and old.?[i] == data[i]) continue;
        spriteByte(px, k, ln, bi, y0, data[i], ghost);
    };
}

fn cursorBox(px: []u8, c: Cursor) void {
    const x0 = @as(usize, c.x) + 16; // VIC x 24 is the window's left edge, plane 40
    const y0 = WIN_Y + (@as(usize, c.y) -| 34);
    const step: usize = if (c.wide) 2 else 1;
    for (CURSOR_BOX, 0..) |row, ry| for (0..9) |bx| {
        if (row & (@as(u16, 0x100) >> @intCast(bx)) != 0) for (0..step) |d| put(px, x0 + bx * step + d, y0 + ry, c.col);
    };
}

/// The cells a cursor box can touch (it hangs 1 px below and right of its first cell).
fn cursorCells(c: Cursor, hit: *[dsp.ROWS][dsp.COLS]bool) void {
    const cx = (@as(usize, c.x) -| 24) / 8;
    const cy = (@as(usize, c.y) -| 34) / 8;
    const w: usize = if (c.wide) 3 else 2;
    for (cy..@min(cy + 2, dsp.ROWS)) |r| for (cx..@min(cx + w, dsp.COLS)) |cc| {
        hit[r][cc] = true;
    };
}

/// Bring the plane `px` (W*H indices) to `scr` (+ the editor's overlay, border and cursor), storing
/// only what differs from the shadow. `over`/`b` null: a plain 25-row text screen (dialogs).
pub fn present(sh: *Shadow, px: []u8, scr: *const dsp.Screen, over: ?*const dsp.Overlay, b: ?*const border.Border, cur: ?Cursor) void {
    const editor = over != null and b != null;
    const full = !sh.drawn or sh.editor != editor;
    if (full) {
        @memset(px[0 .. W * H], 0);
        sh.cursor = null;
    }
    var hit: [dsp.ROWS][dsp.COLS]bool = [_][dsp.COLS]bool{[_]bool{false} ** dsp.COLS} ** dsp.ROWS;
    if (sh.cursor) |c| cursorCells(c, &hit);
    for (0..dsp.ROWS) |r| for (0..dsp.COLS) |c| {
        if (full or hit[r][c] or sh.scr.chars[r][c] != scr.chars[r][c] or sh.scr.colours[r][c] != scr.colours[r][c])
            cell(px, r, c, scr.chars[r][c], scr.colours[r][c]);
    };
    sh.scr = scr.*;
    if (editor) editorLayers(sh, px, over.?, b.?, full);
    sh.cursor = null;
    if (cur) |c| {
        cursorBox(px, c);
        sh.cursor = c;
    }
    sh.drawn = true;
    sh.editor = editor;
}

fn editorLayers(sh: *Shadow, px: []u8, over: *const dsp.Overlay, b: *const border.Border, full: bool) void {
    if (full) bars(px, frame.bar_col);
    for (0..dsp.COLS) |c| if (full or sh.row26[c] != over.row26[c]) row26Cell(px, c, over.row26[c]);
    sh.row26 = over.row26;
    sprites(px, b.up[0x40..], if (full) null else sh.up[0x40..], UP_Y, false);
    sprites(px, &b.low, if (full) null else &sh.low, LOW_Y, true);
    sh.up = b.up;
    sh.low = b.low;
}

test "a full repaint equals frame.compose, and so does an incremental one after a change" {
    const editor = @import("editor.zig");
    var e: editor.Editor = editor.Editor.init();
    try e.load(@embedFile("tunes/FLASHITBACK.SWM"));
    var scr: dsp.Screen = undefined;
    var over: dsp.Overlay = .{};
    var b = border.Border.init();
    var sh: Shadow = .{};
    const px = try std.testing.allocator.alloc(u8, W * H);
    defer std.testing.allocator.free(px);
    const want = try std.testing.allocator.create(frame.Frame);
    defer std.testing.allocator.destroy(want);
    for (0..2) |round| {
        if (round == 1) _ = e.key(.{ .code = 7 }); // cursor down: the text, the 26th row and the sprites change
        e.render(&scr);
        e.overlay(&over);
        border.upperRender(&b, &over);
        border.lowerRender(&b, &over);
        present(&sh, px, &scr, &over, &b, null);
        frame.compose(want, &scr, &over, &b);
        for (0..H) |y| try std.testing.expectEqualSlices(u8, &want.px[y], px[y * W ..][0..W]);
    }
}
