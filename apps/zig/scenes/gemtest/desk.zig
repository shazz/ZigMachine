// --------------------------------------------------------------------------
// GEMTEST's own desktop (G16; Matt on the board, 9 Nov: "on the green desktop
// behind GEMTEST, show icons to test behaviours"): a WF_NEWDESK tree in the
// program's memory (rom.aes.obj.setDesk), the green desk its root and four G_ICONs
// along its bottom, the ROM's own icons by number. The ROM draws it wherever the
// desk shows (its WM_REDRAW rectangles, redraws.zig). A click selects an icon (the
// others deselect, an empty spot deselects all), a drag moves it, a double-click
// opens it (the Icons area, which says which one).
// --------------------------------------------------------------------------
const rom = @import("rom_sdk");
const O = rom.aes.obj;
const redraw = rom.aes.redraw;
const Rect = rom.Rect;
const screen = @import("../notepad/screen.zig");

pub const N = 4;
pub const W: i16 = 72; // an icon's box: the 32 px image over its 8 px label
pub const H: i16 = 42;
const SYS = [N]u32{ O.SYS_FLOPPY, O.SYS_HARD, O.SYS_PROGRAM, O.SYS_TRASH };
pub const NAMES = [N][:0]const u8{ "FLOPPY", "CARD", "GEMTEST", "TRASH" };
const GREEN = O.boxSpec(0, 0, 0x01F3); // no border, solid GEM green (the desktop's colour)

pub const Desk = struct {
    objs: [1 + N]O.Object = undefined,
    blks: [N]O.Iconblk = undefined,
    drag: ?u8 = null, // the icon a press started on
    from: [2]i32 = .{ 0, 0 },
    opened: ?u8 = null, // the last icon opened (a double-click)
    prev: bool = false, // the pointer's button last frame
    ghost: bool = true, // Mode > Drag ghost: a dotted box follows the pointer (desk_drag.zig)
    snap: bool = false, // Mode > Snap to grid: icons land on the layout's grid
    shown: ?Rect = null, // the ghost on screen now

    /// The tree for a `mode` screen, registered as the program's desktop.
    pub fn init(self: *Desk, g: rom.Gui, mode: rom.aes.ScreenMode) void {
        const w = screen.width(mode);
        const h = screen.height(mode);
        self.objs[0] = .{ .head = 1, .tail = N, .ty = O.G_BOX, .spec = GREEN, .x = 0, .y = 11, .w = w, .h = h - 11 };
        for (0..N) |k| {
            self.blks[k] = .{ .pdata = SYS[k], .ptext = O.addr(NAMES[k].ptr), .xicon = 20, .ytext = 33 };
            const next: i16 = if (k + 1 < N) @intCast(k + 2) else 0;
            self.objs[1 + k] = .{ .next = next, .ty = O.G_ICON, .flags = O.SELECTABLE, .spec = O.addr(&self.blks[k]), .x = @intCast(8 + k * 80), .y = h - 11 - H - 4, .w = W, .h = H };
        }
        self.objs[N].flags |= O.LASTOB;
        O.setDesk(g, &self.objs);
    }

    /// Icon `k`'s box on screen.
    pub fn box(self: *const Desk, k: usize) Rect {
        const o = self.objs[1 + k];
        return .{ .x = self.objs[0].x + o.x, .y = self.objs[0].y + o.y, .w = o.w, .h = o.h };
    }
};

/// The desk inside `r`: the program's tree when registered, else the plain green.
pub fn paint(g: rom.Gui, mode: rom.aes.ScreenMode, r: Rect) void {
    if (!O.drawDesk(g, r)) screen.desk(g, mode);
}

/// `r` of the desk redrawn where the desk shows (no window over it), each piece clipped.
pub fn repaint(g: rom.Gui, mode: rom.aes.ScreenMode, r: Rect) void {
    var it = redraw.rects(g, 0, .visible);
    while (it.next()) |v| {
        const x0 = @max(v.x, r.x);
        const y0 = @max(v.y, r.y);
        const x1 = @min(v.x + v.w, r.x + r.w);
        const y1 = @min(v.y + v.h, r.y + r.h);
        if (x1 <= x0 or y1 <= y0) continue;
        const c: Rect = .{ .x = x0, .y = y0, .w = x1 - x0, .h = y1 - y0 };
        redraw.clip(g, c);
        paint(g, mode, c);
    }
    redraw.clipOff(g);
}

/// Is (x, y) on the desk (no window there, below the menu bar)?
pub fn onDesk(g: rom.Gui, x: i32, y: i32) bool {
    var it = redraw.rects(g, 0, .visible);
    while (it.next()) |v| if (x >= v.x and y >= v.y and x < v.x + v.w and y < v.y + v.h) return true;
    return false;
}
