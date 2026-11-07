// --------------------------------------------------------------------------
// MP3 PLAYER: the screen, one text plane, drawn only when what it shows
// changed (the selection, the track, the state, the second, the load).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const List = @import("list.zig").List;

pub const PLANE = 0;
const BG: u8 = 0;
const INK: u8 = 1;
const SEL: u8 = 2;
const DIM: u8 = 3;
pub const ROWS: usize = 13;

pub const Shown = struct {
    sel: usize,
    top: usize,
    playing: ?usize,
    word: u32,
    secs: u32,
    load: u32,
    n: usize,
};

pub fn palette(os: *ZigOS) void {
    os.setBackgroundColor(.{ .r = 0, .g = 0, .b = 0, .a = 255 });
    const fb = &os.lfbs[PLANE];
    fb.is_enabled = true;
    fb.setPaletteEntry(BG, .{ .r = 0, .g = 0, .b = 32, .a = 255 });
    fb.setPaletteEntry(INK, .{ .r = 224, .g = 224, .b = 224, .a = 255 });
    fb.setPaletteEntry(SEL, .{ .r = 224, .g = 192, .b = 64, .a = 255 });
    fb.setPaletteEntry(DIM, .{ .r = 128, .g = 128, .b = 160, .a = 255 });
}

pub fn draw(os: *ZigOS, s: Shown, list: *const List, title: []const u8) void {
    const fb = &os.lfbs[PLANE];
    fb.clearFrameBuffer(BG);
    var buf: [48]u8 = undefined;
    os.printText(fb, fmt(&buf, "MP3 PLAYER   C:\\MUSIC   {d} FILES", .{list.n}), 8, 6, INK, BG);
    if (list.n == 0) os.printText(fb, fmt(&buf, "NO .MP3 IN C:\\MUSIC (GEMDOS {d})", .{list.err}), 8, 30, DIM, BG);
    var r: usize = 0;
    while (r < ROWS and s.top + r < list.n) : (r += 1) {
        const i = s.top + r;
        const mark: []const u8 = if (s.playing == i) "> " else "  ";
        const col = if (i == s.sel) SEL else INK;
        const line = fmt(&buf, "{s}{s:<12} {d:>6} KB", .{ mark, list.items[i].slice(), list.items[i].size >> 10 });
        os.printText(fb, line, 8, 22 + @as(i16, @intCast(r)) * 10, col, BG);
    }
    os.printText(fb, if (title.len > 0) title[0..@min(title.len, 38)] else "", 8, 158, SEL, BG);
    os.printText(fb, status(&buf, s), 8, 170, INK, BG);
    os.printText(fb, "UP/DN RET PLAY  P PAUSE  N/B NEXT/PREV", 8, 182, DIM, BG);
    os.printText(fb, "ESC STOP, AGAIN TO QUIT   NO PAULA SFX", 8, 191, DIM, BG);
}

fn status(buf: []u8, s: Shown) []const u8 {
    if (s.playing == null) return "STOPPED";
    if (s.word == 0) return "NO MP3 PLAYER HERE (SOUND OFF?)";
    const st = [_][]const u8{ "IDLE", "PLAYING", "PAUSED", "ENDED" };
    const rate = [_][]const u8{ "--", "32", "44.1", "48", "?" };
    var lb: [16]u8 = undefined;
    const ls = if (s.load == 0) "LOAD --" else std.fmt.bufPrint(&lb, "BARD {d}.{d}%", .{ s.load / 10, s.load % 10 }) catch "?";
    return fmt(buf, "{s} {d:0>2}:{d:0>2} {s}K {s} {s}", .{
        st[s.word & 3],     s.secs / 60, s.secs % 60, rate[@min((s.word >> 4) & 15, 4)],
        if (s.word & 0x100 != 0) "ST" else "MONO", ls,
    });
}

fn fmt(buf: []u8, comptime f: []const u8, args: anytype) []const u8 {
    return std.fmt.bufPrint(buf, f, args) catch buf[0..0];
}
