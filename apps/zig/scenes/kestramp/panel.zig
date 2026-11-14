// --------------------------------------------------------------------------
// KESTRAMP: the window's pixels. The panel is drawn ONCE; after that each
// region is redrawn only when its part of the state moved (a store and every
// enabled plane cost on the board). One text plane, 320 x 200, integers only.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const List = @import("../mp3_player/list.zig").List;
const lcd = @import("lcd.zig");
const list_view = @import("list_view.zig");
const L = @import("layout.zig");

pub const PLANE = L.PLANE;
pub const ROWS = L.ROWS;
const BG = L.BG;
const INK = L.INK;
const GOLD = L.GOLD;
const DIM = L.DIM;
const LIT_FACE = L.LIT_FACE;
const BEVEL_LIGHT = L.BEVEL_LIGHT;
const BEVEL_DARK = L.BEVEL_DARK;
const TRACK_BG = L.TRACK_BG;

const STATUS_TEXT = [_][]const u8{ "STOPPED", "PLAYING", "PAUSED", "NO SOUND (MP3 PLAYER OFF)" };
const BTN_LABEL = [6][]const u8{ "PREV", "PLAY", "PAUSE", "STOP", "NEXT", "OPEN" };
const TOG_LABEL = [2][]const u8{ "SHUFFLE", "REPEAT" };

pub const Status = enum(u8) { stopped, playing, paused, nosound };
pub const Btn = enum(u3) { prev, play, pause, stop, next, open };

/// Everything the window shows; a region is redrawn when its fields change.
pub const Shown = struct {
    secs: u32,
    rate: u32, // tenths of a kHz, 0 when nothing plays
    stereo: bool,
    title_gen: u32, // counts the tracks, so a new title redraws the box
    scroll: u32, // the title's offset in pixels
    pos: u32, // the position bar, in pixels
    status: Status,
    track: usize, // 1-based, 0 when stopped
    n: usize,
    buttons: u8, // bit i = Btn i lit
    toggles: u8, // bit 0 shuffle, bit 1 repeat
    list_open: bool,
    top: usize,
    sel: usize,
};

pub fn palette(os: *ZigOS) void {
    os.setBackgroundColor(.{ .r = 0, .g = 0, .b = 0, .a = 255 });
    const fb = &os.lfbs[PLANE];
    fb.is_enabled = true;
    fb.setPaletteEntry(BG, .{ .r = 16, .g = 24, .b = 32, .a = 255 });
    fb.setPaletteEntry(INK, .{ .r = 208, .g = 208, .b = 208, .a = 255 });
    fb.setPaletteEntry(lcd.LIT, .{ .r = 96, .g = 255, .b = 96, .a = 255 });
    fb.setPaletteEntry(lcd.GHOST, .{ .r = 24, .g = 64, .b = 24, .a = 255 });
    fb.setPaletteEntry(BEVEL_LIGHT, .{ .r = 110, .g = 120, .b = 140, .a = 255 });
    fb.setPaletteEntry(BEVEL_DARK, .{ .r = 8, .g = 8, .b = 12, .a = 255 });
    fb.setPaletteEntry(L.FACE, .{ .r = 48, .g = 56, .b = 72, .a = 255 });
    fb.setPaletteEntry(GOLD, .{ .r = 240, .g = 192, .b = 64, .a = 255 });
    fb.setPaletteEntry(DIM, .{ .r = 112, .g = 120, .b = 140, .a = 255 });
    fb.setPaletteEntry(lcd.LCD_BG, .{ .r = 4, .g = 14, .b = 6, .a = 255 });
    fb.setPaletteEntry(LIT_FACE, .{ .r = 96, .g = 72, .b = 16, .a = 255 });
    fb.setPaletteEntry(TRACK_BG, .{ .r = 32, .g = 40, .b = 52, .a = 255 });
}

/// The static parts: the logo line, the frames, the key hints. Drawn once.
fn drawStatic(os: *ZigOS, fb: *LogicalFB) void {
    os.printText(fb, "KESTRAMP", 6, 3, GOLD, BG);
    os.printText(fb, "MP3 FOR THE KESTREL", 160, 3, DIM, BG);
    fb.fillRect(6, 11, 306, 1, BEVEL_DARK);
    frame(fb, lcd.TIME_X - 1, lcd.TIME_Y - 1, lcd.TIME_W + 2, lcd.TIME_H + 2);
    frame(fb, lcd.TITLE_X - 1, lcd.TITLE_Y - 1, lcd.TITLE_W + 2, 26); // the title and its rate line
    frame(fb, L.BAR_X - 1, L.BAR_Y - 1, L.BAR_W + 2, L.BAR_H + 2);
    os.printText(fb, "Z PREV X PLAY C PAUSE V STOP B NEXT", 6, 182, DIM, BG);
    os.printText(fb, "L OPEN S SHUFFLE R REPEAT ESC LEAVE", 6, 191, DIM, BG);
}

fn frame(fb: *LogicalFB, x: i32, y: i32, w: usize, h: usize) void {
    fb.fillRect(x, y, w, 1, BEVEL_DARK);
    fb.fillRect(x, y + @as(i32, @intCast(h)) - 1, w, 1, BEVEL_DARK);
    fb.fillRect(x, y, 1, h, BEVEL_DARK);
    fb.fillRect(x + @as(i32, @intCast(w)) - 1, y, 1, h, BEVEL_DARK);
}

/// A bevelled box with a centred label; lit boxes get the dark-gold face and gold ink.
fn drawBox(os: *ZigOS, fb: *LogicalFB, x: i32, y: i32, w: usize, h: usize, label: []const u8, lit: bool) void {
    const face: u8 = if (lit) LIT_FACE else L.FACE;
    fb.fillRect(x, y, w, h, face);
    fb.fillRect(x, y, w, 1, BEVEL_LIGHT);
    fb.fillRect(x, y, 1, h, BEVEL_LIGHT);
    fb.fillRect(x, y + @as(i32, @intCast(h)) - 1, w, 1, BEVEL_DARK);
    fb.fillRect(x + @as(i32, @intCast(w)) - 1, y, 1, h, BEVEL_DARK);
    const tx: i16 = @intCast(x + @as(i32, @intCast((w - label.len * 8) / 2)));
    const ty: i16 = @intCast(y + @as(i32, @intCast((h - 8) / 2)));
    os.printText(fb, label, tx, ty, if (lit) GOLD else INK, face);
}

fn drawPos(fb: *LogicalFB, px: u32) void {
    fb.fillRect(L.BAR_X, L.BAR_Y, L.BAR_W, L.BAR_H, TRACK_BG);
    if (px > 0) fb.fillRect(L.BAR_X, L.BAR_Y, @intCast(px), L.BAR_H, lcd.LIT);
}

fn drawButtons(os: *ZigOS, fb: *LogicalFB, mask: u8) void {
    for (BTN_LABEL, 0..) |label, i| {
        const lit = mask & (@as(u8, 1) << @intCast(i)) != 0;
        drawBox(os, fb, L.btnX(i), L.BTN_Y, L.BTN_W, L.BTN_H, label, lit);
    }
}

fn drawToggles(os: *ZigOS, fb: *LogicalFB, mask: u8) void {
    for (TOG_LABEL, 0..) |label, i| {
        const lit = mask & (@as(u8, 1) << @intCast(i)) != 0;
        drawBox(os, fb, L.TOG_X[i], L.TOG_Y, L.TOG_W, L.TOG_H, label, lit);
    }
}

fn drawStatus(os: *ZigOS, fb: *LogicalFB, s: Shown) void {
    fb.fillRect(6, L.STATUS_Y, 306, 9, BG);
    var buf: [48]u8 = undefined;
    const word = STATUS_TEXT[@intFromEnum(s.status)];
    const line = (if (s.track == 0)
        std.fmt.bufPrint(&buf, "{s}  --/{d:0>2}", .{ word, s.n })
    else
        std.fmt.bufPrint(&buf, "{s}  {d:0>2}/{d:0>2}", .{ word, s.track, s.n })) catch return;
    os.printText(fb, line, 6, L.STATUS_Y + 1, INK, BG);
}

/// Draw the window: everything when `old` is null (the first frame), else only the changed regions.
pub fn redraw(os: *ZigOS, old: ?Shown, s: Shown, title: []const u8, list: *const List) void {
    const fb = &os.lfbs[PLANE];
    const full = old == null;
    if (full) {
        fb.clearFrameBuffer(BG);
        drawStatic(os, fb);
    }
    const o = old orelse s;
    if (full or o.secs != s.secs) lcd.drawTime(fb, s.secs);
    if (full or o.title_gen != s.title_gen or o.scroll != s.scroll) lcd.drawTitle(os, fb, title, s.scroll);
    if (full or o.rate != s.rate or o.stereo != s.stereo) lcd.drawInfo(os, fb, s.rate, s.stereo);
    if (full or o.pos != s.pos) drawPos(fb, s.pos);
    if (full or o.buttons != s.buttons) drawButtons(os, fb, s.buttons);
    if (full or o.toggles != s.toggles) drawToggles(os, fb, s.toggles);
    if (full or o.status != s.status or o.track != s.track or o.n != s.n) drawStatus(os, fb, s);
    if (full or o.list_open != s.list_open or o.top != s.top or o.sel != s.sel or o.track != s.track or o.n != s.n)
        list_view.draw(os, fb, list, s.list_open, s.top, s.sel, s.track);
}

/// The bar's pixels for `used` of `size` bytes (0 with no size).
pub fn barPixels(used: u32, size: u32) u32 {
    if (size == 0) return 0;
    const px = @as(u64, used) * L.BAR_W / size;
    return @intCast(@min(px, L.BAR_W));
}
