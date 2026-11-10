// --------------------------------------------------------------------------
// GEMTEST's Icons area (G16): G_ICON objects drawn by the ROM (objc_draw): the
// desktop's six icons by number (ICONBLK with no mask: the ROM's own set, the
// asset set's where one is built in) and one of the program's own, its 1 bpp image
// in the program's memory; and which desk icon a double-click opened.
// --------------------------------------------------------------------------
const std = @import("std");
const rom = @import("rom_sdk");
const O = rom.aes.obj;
const Pen = @import("pen.zig").Pen;
const App = @import("../gemtest.zig").App;
const desk = @import("desk.zig");

const NAMES = [_][:0]const u8{ "FLOPPY", "HARD", "TRASH", "FOLDER", "PROGRAM", "DOC", "OWN" };
const N = NAMES.len;

// The program's own icon: a 32 x 16 frame with a diagonal, rows of 4 bytes (word-padded), and its mask.
const OWN_DATA = blk: {
    var d: [16 * 4]u8 = @splat(0);
    for (0..16) |y| {
        const row: u32 = if (y == 0 or y == 15) 0xFFFFFFFF else (0x80000001 | (@as(u32, 0x60000000) >> @intCast(y * 2)));
        for (0..4) |b| d[y * 4 + b] = @truncate(row >> @intCast(24 - b * 8));
    }
    break :blk d;
};
const OWN_MASK: [16 * 4]u8 = @splat(0xFF);

var objs: [1 + N]O.Object = undefined;
var blks: [N]O.Iconblk = undefined;

fn build() void {
    objs[0] = .{ .head = 1, .tail = N, .ty = O.G_IBOX, .w = 640, .h = 400 };
    for (0..N) |k| {
        blks[k] = .{ .pdata = @intCast(k), .ptext = O.addr(NAMES[k].ptr), .xicon = 20, .ytext = 33 };
        objs[1 + k] = .{ .next = if (k + 1 < N) @intCast(k + 2) else 0, .ty = O.G_ICON, .spec = O.addr(&blks[k]), .w = desk.W, .h = desk.H };
    }
    blks[N - 1] = .{ .pmask = O.addr(&OWN_MASK), .pdata = O.addr(&OWN_DATA), .ptext = O.addr(NAMES[N - 1].ptr), .xicon = 20, .yicon = 8, .hicon = 16, .ytext = 33 };
    objs[N].flags = O.LASTOB;
}

pub fn draw(p: *Pen, app: *App) void {
    build();
    objs[0].x = @intCast(p.ox);
    objs[0].y = @intCast(p.oy);
    p.line("G_ICON, drawn by the ROM (objc_draw): the");
    p.line("desktop's six by number, and one of ours:");
    p.row(desk.H);
    for (0..4) |k| place(p, k);
    p.endRow();
    p.row(desk.H);
    for (4..N) |k| place(p, k);
    p.endRow();
    var b: [48]u8 = undefined;
    const opened = if (app.desk.opened) |k| desk.NAMES[k] else "none yet";
    p.line(std.fmt.bufPrint(&b, "Opened from the desk: {s}", .{opened}) catch "");
    p.line("The desk: click selects, drag moves,");
    p.line("double-click opens (WF_NEWDESK tree)");
    if (p.drawing) (O.Tree{ .g = app.g, .objs = &objs }).draw(0, 8, p.work);
}

fn place(p: *Pen, k: usize) void {
    const xy = p.at(desk.W);
    objs[1 + k].x = @intCast(xy[0]);
    objs[1 + k].y = @intCast(xy[1]);
}
