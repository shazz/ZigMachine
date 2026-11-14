// --------------------------------------------------------------------------
// GEM 5's program API, window redraws (system table 1.22; the ROM half is
// rom/rom_app_redraw.zig): WM_REDRAW rectangle lists, WF_FIRSTXYWH / WF_NEXTXYWH,
// the stack, and the clip. A frame after processWindows:
//
//   var k: u32 = 0;
//   while (redraw.stackAt(g, k)) |id| : (k += 1) {        // back to front
//       var it = redraw.rects(g, id, .redraw);              // this frame's damage of it
//       while (it.next()) |r| { redraw.clip(g, r); win.draw(); drawWork(); }
//   }
//   redraw.clipOff(g);
//
// id 0 is the desk (what no window covers). Reached as `rom.aes.redraw`.
// --------------------------------------------------------------------------
const rom = @import("rom.zig");
const Rect = rom.Rect;

pub extern fn winRects(h: u32, id: u32, which: u32) u32;
pub extern fn winRect(h: u32, i: u32, part: u32) i32;
pub extern fn winStack(h: u32, k: u32) u32;
pub extern fn guiClip(h: u32, x: i32, y: i32, w: i32, hh: i32) void;

pub const Which = enum(u32) { redraw = 0, visible = 1 };

/// A window's rectangles, one at a time (the list is the ROM's until the next rects call).
pub const Iter = struct {
    g: rom.Gui,
    n: u32,
    i: u32 = 0,

    pub fn next(self: *Iter) ?Rect {
        if (self.i >= self.n) return null;
        defer self.i += 1;
        return .{
            .x = @intCast(winRect(self.g.h, self.i, 0)),
            .y = @intCast(winRect(self.g.h, self.i, 1)),
            .w = @intCast(winRect(self.g.h, self.i, 2)),
            .h = @intCast(winRect(self.g.h, self.i, 3)),
        };
    }
};

/// Window `id`'s rectangles (an aes.Window's id; 0 the desk).
pub fn rects(g: rom.Gui, id: u32, which: Which) Iter {
    return .{ .g = g, .n = winRects(g.h, id, @intFromEnum(which)) };
}

/// The id of the k-th open window from the back, null past the top one.
pub fn stackAt(g: rom.Gui, k: u32) ?u32 {
    const id = winStack(g.h, k);
    return if (id == 0) null else id;
}

pub fn clip(g: rom.Gui, r: Rect) void {
    guiClip(g.h, r.x, r.y, r.w, r.h);
}
pub fn clipOff(g: rom.Gui) void {
    guiClip(g.h, 0, 0, 0, 0);
}
