// --------------------------------------------------------------------------
// GEM 5's program API: a program's window (wind_create .. wind_get), split out of
// aes.zig (reached as rom.aes.Window). The externs are aes.zig's.
// --------------------------------------------------------------------------
const rom = @import("rom.zig");
const aes = @import("aes.zig");
const Rect = rom.Rect;
const winOpen = aes.winOpen;
const winClose = aes.winClose;
const winTitle = aes.winTitle;
const winInfo = aes.winInfo;
const winScroll = aes.winScroll;
const winSet = aes.winSet;
const winEvents = aes.winEvents;
const winDraw = aes.winDraw;
const winDrawBars = aes.winDrawBars;
const winGet = aes.winGet;

fn p(s: []const u8) u32 {
    return @intCast(@intFromPtr(s.ptr));
}
fn n(s: []const u8) u32 {
    return @intCast(s.len);
}

/// A program's window (wind_create/wind_open/wind_set/wind_get).
pub const Window = struct {
    g: rom.Gui,
    id: u32 = 0,

    pub fn open(g: rom.Gui, r: Rect, title_: []const u8) ?Window {
        const id = winOpen(g.h, r.x, r.y, r.w, r.h, p(title_), n(title_));
        return if (id == 0) null else .{ .g = g, .id = id };
    }
    pub fn close(self: Window) void {
        winClose(self.g.h, self.id);
    }
    pub fn title(self: Window, s: []const u8) void {
        winTitle(self.g.h, self.id, p(s), n(s));
    }
    pub fn info(self: Window, s: []const u8) void {
        winInfo(self.g.h, self.id, p(s), n(s));
    }
    pub fn scroll(self: Window, vertical: bool, size: i32, pos: i32, max: i32, page: i32) void {
        winScroll(self.g.h, self.id, @intFromBool(vertical), size, pos, max, page);
    }
    pub fn set(self: Window, r: Rect) void {
        winSet(self.g.h, self.id, r.x, r.y, r.w, r.h);
    }
    pub fn events(self: Window) u32 {
        return winEvents(self.g.h, self.id);
    }
    pub fn draw(self: Window) void {
        winDraw(self.g.h, self.id);
    }
    /// The scrollbars only (after scroll() moved or resized a slider).
    pub fn drawBars(self: Window) void {
        winDrawBars(self.g.h, self.id);
    }
    pub fn work(self: Window) Rect {
        return self.rectAt(0);
    }
    pub fn outer(self: Window) Rect {
        return self.rectAt(4);
    }
    fn rectAt(self: Window, at: u32) Rect {
        return .{
            .x = @intCast(winGet(self.g.h, self.id, at)),
            .y = @intCast(winGet(self.g.h, self.id, at + 1)),
            .w = @intCast(winGet(self.g.h, self.id, at + 2)),
            .h = @intCast(winGet(self.g.h, self.id, at + 3)),
        };
    }
    pub fn vscroll(self: Window) i32 {
        return winGet(self.g.h, self.id, 8);
    }
    pub fn hscroll(self: Window) i32 {
        return winGet(self.g.h, self.id, 9);
    }
};

