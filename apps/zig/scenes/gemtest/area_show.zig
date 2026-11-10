// --------------------------------------------------------------------------
// GEMTEST's Windows and Text areas: content that only shows. The Windows area's
// four windows each tell what they are, where they sit in the stack and how many
// of each event the program received; the GADGETS window has a numbered grid to
// scroll both ways. The Text area: the system font, a long and a wide text.
// --------------------------------------------------------------------------
const std = @import("std");
const rom = @import("rom_sdk");
const aes = rom.aes;
const Pen = @import("pen.zig").Pen;
const App = @import("../gemtest.zig").App;

pub fn windows(p: *Pen, app: *App, i: u8) void {
    const s = &app.wins.slots[i];
    var b: [64]u8 = undefined;
    p.line(fmt(&b, "Window {d} of {d}, stack {d} (1 = back)", .{ i + 1, app.wins.n, app.wins.depth(i) }));
    p.line(fmt(&b, "Events: moved {d} sized {d} topped {d}", .{ s.moved, s.sized, s.topped }));
    p.line(fmt(&b, "Scrolled {d}: row {d}, column {d}", .{ s.scrolled, s.top, s.left }));
    const wk = s.win.work();
    p.line(fmt(&b, "Work area {d},{d} {d}x{d}", .{ wk.x, wk.y, wk.w, wk.h }));
    p.gap();
    if (s.part == 0) return grid(p);
    if (s.part == 3) p.line("Larger than the screen: the ROM clips it.");
    p.line("Redrawn: only the ROM's WM_REDRAW");
    p.line(" rectangles (aes.redraw), clipped:");
    p.line(" the desk's, then each window's,");
    p.line(" back to front (winStack)");
}

// 40 rows of 24 cells, "r00c00": the sliders' size and position show the scroll.
fn grid(p: *Pen) void {
    var b: [24 * 7]u8 = undefined;
    for (0..40) |r| {
        var n: usize = 0;
        for (0..24) |c| {
            const cell = std.fmt.bufPrint(b[n..], "r{d:0>2}c{d:0>2} ", .{ r, c }) catch break;
            n += cell.len;
        }
        p.line(b[0..n]);
    }
}

const LOREM = [_][]const u8{
    "GEM, the Graphics Environment Manager, came to the ST in 1985.",
    "Its AES gave programs windows, menus, dialogs and alerts;",
    "its VDI drew the lines, the fills and the text.",
    "This window is a long text: scroll it with the arrows,",
    "the slider or a click in the track (a page at a time).",
};

pub fn text(p: *Pen) void {
    const c = aes.cell(p.g);
    var b: [240]u8 = undefined;
    p.line(fmt(&b, "System font: {d}x{d} cells (guiCell)", .{ c[0], c[1] }));
    p.missing("other sizes (vst_height)");
    p.missing("the 8x16 system font");
    p.missing("styles: bold, light, italic,");
    p.missing("  underlined, outlined (vst_effects)");
    p.missing("other fonts (vst_font, GDOS)");
    p.gap();
    p.line(wide(&b));
    p.line("The line above is 200 columns wide: scroll across.");
    p.gap();
    for (0..100) |i| p.line(fmt(&b, "{d:0>3}  {s}", .{ i + 1, LOREM[i % LOREM.len] }));
    p.line("--- the end of the text ---");
}

// A ruler 200 columns wide: "....:....1....:....2" and on.
fn wide(b: *[240]u8) []const u8 {
    for (0..200) |i| {
        const n = i + 1;
        b[i] = if (n % 10 == 0) '0' + @as(u8, @intCast((n / 10) % 10)) else if (n % 5 == 0) ':' else '.';
    }
    return b[0..200];
}

fn fmt(b: []u8, comptime f: []const u8, args: anytype) []const u8 {
    return std.fmt.bufPrint(b, f, args) catch b[0..0];
}
