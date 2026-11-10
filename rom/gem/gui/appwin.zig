// --------------------------------------------------------------------------
// A PROGRAM's windows (GEM 5's app API, rom/rom_app.zig): wind_create / wind_open /
// wind_set / wind_get and the WM_* messages, for a cart. The window manager is the
// desktop's own (window.zig Wm: the same gadgets, outline move and size, sliders,
// track paging), driven a frame at a time; what changed comes back as event bits,
// as the AES's messages did, so the program redraws only what they name:
//
//   EV_WORK      a press started in the top window's work area: the program's own
//   EV_HIT       the press landed on a window's gadgets: not the program's
//   EV_CLOSED    the closer was clicked (WM_CLOSED: a REQUEST, the window stays open
//                until the program calls close, after "Save changes?" say)
//   EV_MOVED / EV_SIZED   the window's box changed (a drag, a size, the fuller)
//   EV_SCROLLED  an arrow, a slider or a track page moved vscroll / hscroll
//   EV_TOPPED    another window came to the front
//
// The move/size outline is drawn save-under (saveunder.zig): nothing to redraw until the
// gesture ends, then only the WM_REDRAW rectangles (appwin_damage.zig). Arrows repeat held.
// --------------------------------------------------------------------------
const types = @import("types.zig");
const window = @import("window.zig");
const chrome = @import("chrome.zig");
const frame = @import("appwin_frame.zig");
const Gui = @import("core.zig").Gui;
const saveunder = @import("saveunder.zig");
const winsize = @import("winsize.zig");
pub const dmg = @import("appwin_damage.zig");
const Rect = types.Rect;
const MAX_WIN = types.MAX_WIN;

pub const EV_WORK: u32 = 1;
pub const EV_HIT: u32 = 2;
pub const EV_CLOSED: u32 = 4;
pub const EV_MOVED: u32 = 8;
pub const EV_SIZED: u32 = 16;
pub const EV_SCROLLED: u32 = 32;
pub const EV_TOPPED: u32 = 64;

pub const TITLE_MAX = 40;
// The outline of a 640x480 window: (640 + 480 + 2) dots and a margin, in the lent scratch.
pub const OUTLINE_DOTS = 1200;

pub const Snap = struct { r: Rect, v: i16, h: i16, open: bool };

pub const AppWin = struct {
    wm: window.Wm = .{},
    titles: [MAX_WIN][TITLE_MAX]u8 = undefined,
    infos: [MAX_WIN][TITLE_MAX]u8 = undefined,
    shown: [MAX_WIN]Snap = undefined,
    events: [MAX_WIN]u32 = [_]u32{0} ** MAX_WIN,
    top: ?u8 = null,
    held: u16 = 0,
    held_win: ?u8 = null,
    outline: saveunder.Outline = .{}, // its buffers are lent (guiScratch)
    dirty: dmg.RectList = .{}, // the damage since the last process() (appwin_damage.zig: WM_REDRAW)

    pub fn reset(self: *AppWin) void {
        self.wm = .{};
        self.dirty = .{};
        self.events = [_]u32{0} ** MAX_WIN;
        self.top = null;
        self.held_win = null;
        self.outline.at = null;
    }

    fn valid(self: *const AppWin, id: u32) bool {
        return id < self.wm.n and self.wm.wins[id].open;
    }

    /// wind_create + wind_open: the window's id, null when all MAX_WIN are open.
    pub fn open(self: *AppWin, r: Rect, title: []const u8) ?u8 {
        const id = self.wm.tryAdd(.{ .r = r, .title = "" }) orelse return null;
        self.setTitle(id, title);
        self.shown[id] = snap(&self.wm.wins[id]);
        self.events[id] = 0;
        self.top = self.wm.topOpen();
        self.dirty.add(coverOf(&self.wm.wins[id]));
        return id;
    }

    pub fn close(self: *AppWin, id: u32) void {
        if (!self.valid(id)) return;
        self.dirty.add(coverOf(&self.wm.wins[id])); // what was under it is exposed
        self.wm.wins[id].open = false;
        _ = self.wm.takeClosed();
        self.shown[id].open = false;
        self.top = self.wm.topOpen();
        self.titleDirt(self.top); // the window under it may be the top now: its title hatched
    }

    pub fn setTitle(self: *AppWin, id: u32, s: []const u8) void {
        if (id >= self.wm.n) return;
        const n = @min(s.len, TITLE_MAX);
        @memcpy(self.titles[id][0..n], s[0..n]);
        self.wm.wins[id].title = self.titles[id][0..n];
    }
    pub fn setInfo(self: *AppWin, id: u32, s: []const u8) void {
        if (id >= self.wm.n) return;
        const n = @min(s.len, TITLE_MAX);
        @memcpy(self.infos[id][0..n], s[0..n]);
        self.wm.wins[id].info = self.infos[id][0..n];
    }

    /// wind_set WF_VSLIDE/WF_VSLSIZE and the horizontal pair, plus the page a track click moves.
    pub fn setScroll(self: *AppWin, id: u32, vertical: bool, size: i32, pos: i32, max: i32, page: i32) void {
        if (id >= self.wm.n) return;
        const w = &self.wm.wins[id];
        const m = clampI16(max, 0);
        const s = clampI16(size, 0);
        const at: i16 = @min(m, clampI16(pos, 0));
        if (vertical) {
            w.vslide = @min(s, 1000);
            w.vmax = m;
            w.vscroll = at;
            w.vpage = @max(1, clampI16(page, 1));
            self.shown[id].v = at;
        } else {
            w.hslide = @min(s, 1000);
            w.hmax = m;
            w.hscroll = at;
            w.hpage = @max(1, clampI16(page, 1));
            self.shown[id].h = at;
        }
    }

    /// wind_set WF_CURRXYWH: as a size drag, never past the screen's edge nor under the gadgets'
    /// room (winsize.zig: G22, G23); the move part is the program's.
    pub fn setRect(self: *AppWin, id: u32, r: Rect, screen_w: i16, screen_h: i16) void {
        if (id >= self.wm.n) return;
        const w = &self.wm.wins[id];
        self.dirty.add(coverOf(w));
        var c = r;
        c.w = @max(winsize.minW(w.min_w), @min(r.w, screen_w - r.x));
        c.h = @max(winsize.minH(w.min_h, types.topBarsH(w)), @min(r.h, screen_h - r.y));
        w.r = c;
        self.shown[id].r = c;
        self.dirty.add(coverOf(w));
    }

    /// Window `id`'s title bar is stale (it became, or stopped being, the top window).
    pub fn titleDirt(self: *AppWin, id: ?u8) void {
        const i = id orelse return;
        const w = &self.wm.wins[i];
        if (w.open) self.dirty.add(.{ .x = w.r.x, .y = w.r.y, .w = w.r.w, .h = types.TITLE_H });
    }

    /// The windows as the damage pass sees them: covers by id, the open ones back to front.
    pub fn stack(self: *const AppWin) dmg.Stack {
        var s: dmg.Stack = .{};
        for (self.wm.order[0..self.wm.n]) |id| {
            if (!self.wm.wins[id].open) continue;
            s.cover[id] = coverOf(&self.wm.wins[id]);
            s.order[s.n] = id;
            s.n += 1;
        }
        return s;
    }

    pub fn window_(self: *AppWin, id: u32) ?*types.Window {
        return if (id < self.wm.n) &self.wm.wins[id] else null;
    }

    /// One frame of input: every window's events (read with eventsOf), OR'ed together.
    pub fn process(self: *AppWin, g: *Gui) u32 {
        return frame.process(self, g);
    }

    pub fn eventsOf(self: *const AppWin, id: u32) u32 {
        return if (id < MAX_WIN) self.events[id] else 0;
    }

    /// The window's chrome (title bar active when it is the top one); the program draws its
    /// work area after this.
    pub fn draw(self: *AppWin, g: *Gui, id: u32) void {
        if (!self.valid(id)) return;
        _ = self.wm.drawChrome(g, @intCast(id), if (self.wm.topOpen()) |t| t == id else false);
    }

    /// Only the two scrollbars and the size gadget (wind_set's sliders changed: WF_VSLIDE and the
    /// rest redraw these, not the window).
    pub fn drawBars(self: *AppWin, g: *Gui, id: u32) void {
        if (!self.valid(id)) return;
        chrome.scrollbars(g, &self.wm.wins[id]);
    }

    pub fn work(self: *AppWin, id: u32) Rect {
        return if (id < self.wm.n) self.wm.contentRect(@intCast(id)) else .{ .x = 0, .y = 0, .w = 0, .h = 0 };
    }
};

fn coverOf(w: *const types.Window) dmg.Rect {
    return dmg.cover(w.r.x, w.r.y, w.r.w, w.r.h);
}

pub fn snap(w: *const types.Window) Snap {
    return .{ .r = w.r, .v = w.vscroll, .h = w.hscroll, .open = w.open };
}

fn clampI16(v: i32, lo: i32) i16 {
    return @intCast(@max(lo, @min(@as(i32, 32767), v)));
}
