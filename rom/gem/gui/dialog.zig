// --------------------------------------------------------------------------
// Modal dialog — a centred GEM box: an alert (message + OK) or a file selector
// (a list + Cancel). While active it owns all input; process() returns a result
// on the frame the user chooses. Draw it LAST, over everything.
// --------------------------------------------------------------------------
const types = @import("types.zig");
const Gui = @import("core.zig").Gui;
const Rect = types.Rect;
const BLACK = types.BLACK;
const WHITE = types.WHITE;

pub const DlgResult = union(enum) { none, ok: u8, cancel };

pub const MAX_LINES = 5; // GEM alerts are at most 5 lines

pub const Dialog = struct {
    active: bool = false,
    filesel: bool = false,
    title: []const u8 = "",
    lines: [MAX_LINES][]const u8 = [_][]const u8{""} ** MAX_LINES,
    // The alert OWNS its text. It used to store the caller's slices and redraw
    // them every frame until dismissed, which is fine for a Zig literal and
    // garbage for a C app that passed a stack buffer — and the ROM's ABI promises
    // a caller's memory is read, never retained. Copy in.
    line_buf: [MAX_LINES][MAX_LINE]u8 = undefined,
    nlines: u8 = 0,
    warn: bool = false, // draw the GEM warning sign in the left gutter
    items: []const []const u8 = &.{},
    want_w: i16 = 0,
    want_h: i16 = 0,

    const MAX_LINE: usize = 48; // a GEM alert line; longer is truncated, not kept
    const ROW_H: i16 = 8; // one char cell per list row (GEM item selector)
    const BTN_H: i16 = 12; // GEM alert buttons are one char row + border
    const LINE_H: i16 = 10; // alert text lines (8px font + leading)
    const SIGN_W: i16 = 40; // left gutter the warning sign lives in

    // GEM alerts have no title bar — every line is body text.
    pub fn alert(self: *Dialog, title: []const u8, msg: []const u8) void {
        self.alertLines(&.{ title, msg }, false);
    }
    // A multi-line GEM alert, optionally with the warning sign on the left.
    pub fn alertLines(self: *Dialog, lines: []const []const u8, warn: bool) void {
        self.* = .{ .active = true, .filesel = false, .warn = warn };
        var widest: i16 = 0;
        for (lines, 0..) |l, i| {
            if (i >= MAX_LINES) break;
            const n = @min(l.len, MAX_LINE);
            @memcpy(self.line_buf[i][0..n], l[0..n]);
            self.lines[i] = self.line_buf[i][0..n]; // our copy, not the caller's
            self.nlines = @intCast(i + 1);
            widest = @max(widest, @as(i16, @intCast(n)));
        }
        self.want_w = widest * 8 + 32 + (if (warn) SIGN_W else 0);
        self.want_h = @as(i16, self.nlines) * LINE_H + 44;
    }
    pub fn openFiles(self: *Dialog, title: []const u8, items: []const []const u8) void {
        self.* = .{ .active = true, .filesel = true, .title = title, .items = items };
        self.nlines = 0;
        self.want_w = 220;
        self.want_h = @as(i16, @intCast(items.len)) * ROW_H + 44;
    }

    // Box: white with a GEM double frame (outer + inner), no shadow — dialogs are
    // flat; only windows cast a drop shadow.
    fn box(g: *Gui, b: Rect) void {
        g.rect(b, WHITE);
        g.frame(b, BLACK);
        g.frame(.{ .x = b.x + 3, .y = b.y + 3, .w = b.w - 6, .h = b.h - 6 }, BLACK);
    }

    pub fn process(self: *Dialog, g: *Gui) DlgResult {
        if (!self.active) return .none;
        // A dialog never hangs off the screen, however long its text is.
        const bw = @min(self.want_w, g.screen_w - 8);
        const b = Rect{ .x = @divTrunc(g.screen_w - bw, 2), .y = @divTrunc(g.screen_h - self.want_h, 2), .w = bw, .h = self.want_h };
        box(g, b);
        if (self.filesel) g.text(self.title, b.x + 8, b.y + 8, BLACK, WHITE);
        const res = if (self.filesel) self.fileList(g, b) else self.alertBody(g, b);
        if (res != .none) self.active = false;
        return res;
    }

    fn alertBody(self: *Dialog, g: *Gui, b: Rect) DlgResult {
        const tx = b.x + 8 + (if (self.warn) SIGN_W else 0);
        var i: u8 = 0;
        while (i < self.nlines) : (i += 1)
            g.text(self.lines[i], tx, b.y + 10 + @as(i16, i) * LINE_H, BLACK, WHITE);
        if (self.warn) warnSign(g, b.x + 12, b.y + 12);
        const ok = Rect{ .x = b.x + @divTrunc(b.w - 56, 2), .y = b.y + b.h - 22, .w = 56, .h = 14 };
        return if (g.buttonThick(ok, "OK", false, 3)) .{ .ok = 0 } else .none;
    }

    // The GEM alert warning sign: an exclamation mark inside a triangle, drawn
    // dot by dot (24x22) rather than shipped as a bitmap.
    fn warnSign(g: *Gui, x: i16, y: i16) void {
        const H: i16 = 22;
        const HALF: i16 = 12;
        var row: i16 = 0;
        while (row < H) : (row += 1) { // the two sloping edges
            const half = @divTrunc(row * HALF, H - 1);
            g.plot(x + HALF - half, y + row, BLACK);
            g.plot(x + HALF + half, y + row, BLACK);
        }
        g.rect(.{ .x = x, .y = y + H - 1, .w = 2 * HALF + 1, .h = 1 }, BLACK); // base
        g.rect(.{ .x = x + HALF - 1, .y = y + 8, .w = 3, .h = 7 }, BLACK); // the "!" stem
        g.rect(.{ .x = x + HALF - 1, .y = y + 17, .w = 3, .h = 2 }, BLACK); // its dot
    }

    // List rows: plain text, inverse video only while the button is held over a
    // row (GEM has no hover highlight); the press picks the row.
    fn fileList(self: *Dialog, g: *Gui, b: Rect) DlgResult {
        var res: DlgResult = .none;
        for (self.items, 0..) |it, j| {
            const row = Rect{ .x = b.x + 8, .y = b.y + 20 + @as(i16, @intCast(j)) * ROW_H, .w = b.w - 16, .h = ROW_H };
            const held = g.down and g.hit(row);
            if (held) g.rect(row, BLACK);
            g.text(it, row.x + 8, row.y, if (held) WHITE else BLACK, if (held) BLACK else WHITE);
            if (g.edge and held) res = .{ .ok = @intCast(j) };
        }
        const cancel = Rect{ .x = b.x + b.w - 64, .y = b.y + b.h - BTN_H - 8, .w = 56, .h = BTN_H };
        if (g.buttonThick(cancel, "Cancel", false, 2)) res = .cancel;
        return res;
    }
};
