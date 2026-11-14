// --------------------------------------------------------------------------
// KESTRAMP: the track list under the transport, while it is open (Open / L):
// C:\MUSIC's files in name order, the selection gold, the playing one marked.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const List = @import("../mp3_player/list.zig").List;
const L = @import("layout.zig");

pub fn draw(os: *ZigOS, fb: *LogicalFB, list: *const List, open: bool, top: usize, sel: usize, track: usize) void {
    fb.fillRect(L.LIST_X, L.LIST_Y, L.LIST_W, L.LIST_H, L.BG);
    if (!open) return;
    if (list.n == 0) return os.printText(fb, "NO .MP3 IN C:\\MUSIC", 8, L.LIST_Y + 2, L.DIM, L.BG);
    var r: usize = 0;
    while (r < L.ROWS and top + r < list.n) : (r += 1) row(os, fb, list, top + r, r, sel, track);
}

fn row(os: *ZigOS, fb: *LogicalFB, list: *const List, i: usize, r: usize, sel: usize, track: usize) void {
    const y: i32 = L.LIST_Y + @as(i32, @intCast(r * L.ROW_H));
    const is_sel = i == sel;
    const bg: u8 = if (is_sel) L.LIT_FACE else L.BG;
    fb.fillRect(L.LIST_X, y, L.LIST_W, L.ROW_H, bg);
    var buf: [40]u8 = undefined;
    const mark: []const u8 = if (track == i + 1) ">" else " ";
    const line = std.fmt.bufPrint(&buf, "{s} {s:<12} {d:>6} KB", .{ mark, list.items[i].slice(), list.items[i].size >> 10 }) catch return;
    os.printText(fb, line, 8, @intCast(y + 1), if (is_sel) L.GOLD else L.INK, bg);
}
