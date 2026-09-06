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

pub const Dialog = struct {
    active: bool = false,
    filesel: bool = false,
    title: []const u8 = "",
    msg: []const u8 = "",
    items: []const []const u8 = &.{},
    want_w: i16 = 0,
    want_h: i16 = 0,

    const ROW_H: i16 = 8; // one char cell per list row (GEM item selector)
    const BTN_H: i16 = 12; // GEM alert buttons are one char row + border

    // GEM alerts have no title bar — `title` is drawn as the first text line.
    pub fn alert(self: *Dialog, title: []const u8, msg: []const u8) void {
        self.* = .{ .active = true, .filesel = false, .title = title, .msg = msg };
        self.want_w = @max(@as(i16, @intCast(msg.len)), @as(i16, @intCast(title.len))) * 8 + 32;
        self.want_h = 56;
    }
    pub fn openFiles(self: *Dialog, title: []const u8, items: []const []const u8) void {
        self.* = .{ .active = true, .filesel = true, .title = title, .items = items };
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
        const b = Rect{ .x = @divTrunc(g.screen_w - self.want_w, 2), .y = @divTrunc(g.screen_h - self.want_h, 2), .w = self.want_w, .h = self.want_h };
        box(g, b);
        g.text(self.title, b.x + 8, b.y + 8, BLACK, WHITE);
        const res = if (self.filesel) self.fileList(g, b) else self.alertBody(g, b);
        if (res != .none) self.active = false;
        return res;
    }

    fn alertBody(self: *Dialog, g: *Gui, b: Rect) DlgResult {
        g.text(self.msg, b.x + 8, b.y + 20, BLACK, WHITE);
        const ok = Rect{ .x = b.x + @divTrunc(b.w - 56, 2), .y = b.y + b.h - 22, .w = 56, .h = 14 };
        return if (g.buttonThick(ok, "OK", false, 3)) .{ .ok = 0 } else .none;
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
