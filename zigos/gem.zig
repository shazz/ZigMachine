// --------------------------------------------------------------------------
// ZigGEM — the "ROM": a GEM-style desktop + the GUI libraries an application
// links against. Think of it as the system in ROM; an app in apps/ is the RAM
// cartridge that plugs into it. The desktop boots first, shows icons, and
// launches an app; the app draws over the whole screen and returns here on quit.
//
// The GUI toolkit (windows, menus, dialogs, buttons) lives in gui.zig and is
// re-exported here as `gem.gui` — the ROM's library surface. Apps use it.
// --------------------------------------------------------------------------
const zsrc = @import("zigos.zig");
pub const gui = @import("gui.zig"); // the ROM's GUI libraries (apps link this)
pub const icons = @import("gem_icons.zig"); // 1bpp icons ripped from a GEM icon sheet

const ZigOS = zsrc.ZigOS;
const LogicalFB = zsrc.LogicalFB;
const Blitter = zsrc.Blitter;
const Rect = gui.Rect;

pub const Action = enum { none, launch, res_low, res_medium };

const DESK_MENUS = [_]gui.Menu{
    .{ .title = "Desk", .items = &.{"About ZigGEM"} },
    .{ .title = "File", .items = &.{"Open"} },
    .{ .title = "View", .items = &.{"Icons"} },
    .{ .title = "Options", .items = &.{ "Low Resolution", "Medium Resolution" } },
};

const GRID: i16 = 16; // icons snap to this grid on drop (GEM-style)

const DeskIcon = struct { x: i16, y: i16, ic: icons.Icon, label: []const u8, is_app: bool };

pub const Desktop = struct {
    g: gui.Gui = undefined,
    menubar: gui.MenuBar = .{},
    items: [3]DeskIcon = .{
        .{ .x = 44, .y = 30, .ic = icons.CARTRIDGE, .label = "ST REPLAY", .is_app = true },
        .{ .x = 580, .y = 22, .ic = icons.FLOPPY, .label = "Floppy", .is_app = false },
        .{ .x = 580, .y = 130, .ic = icons.TRASH, .label = "Trash", .is_app = false },
    },
    drag: ?u8 = null,
    grab_dx: i16 = 0,
    grab_dy: i16 = 0,
    moved: bool = false,

    pub fn init(self: *Desktop, os: *ZigOS, fb: *LogicalFB, blit: *Blitter) void {
        self.g = .{ .os = os, .fb = fb, .blit = blit, .screen_w = 640, .screen_h = 200 };
        self.menubar = .{};
    }

    pub fn setPointer(self: *Desktop, x: i32, y: i32, buttons: u32) void {
        self.g.setPointer(x, y, buttons);
    }
    pub fn beginFrame(self: *Desktop) void {
        self.g.beginFrame();
    }
    pub fn endFrame(self: *Desktop) void {
        self.g.endFrame();
    }

    // Keep icons on-screen (called when the resolution/screen width changes).
    pub fn clampIcons(self: *Desktop) void {
        for (&self.items) |*it| self.clamp(it);
    }
    fn clamp(self: *Desktop, it: *DeskIcon) void {
        it.x = @max(0, @min(it.x, self.g.screen_w - @as(i16, @intCast(it.ic.w))));
        it.y = @max(gui.MENU_H + 2, @min(it.y, 200 - @as(i16, @intCast(it.ic.h)) - 10));
    }

    // Draw the desktop (res-adaptive) + handle icon drag/click; return the action.
    pub fn render(self: *Desktop) Action {
        const g = &self.g;
        const sw = g.screen_w;
        var action: Action = .none;

        // --- input: drag an icon (snap to grid on drop), or click the app icon ---
        if (self.drag) |di| {
            if (!g.down) {
                if (self.moved) self.snap(di) else if (self.items[di].is_app) action = .launch;
                self.drag = null;
            } else {
                const nx: i16 = @intCast(@as(i32, g.px) - self.grab_dx);
                const ny: i16 = @intCast(@as(i32, g.py) - self.grab_dy);
                if (@abs(nx - self.items[di].x) > 1 or @abs(ny - self.items[di].y) > 1) self.moved = true;
                self.items[di].x = nx;
                self.items[di].y = ny;
            }
        } else if (g.edge and g.py >= gui.MENU_H) {
            for (self.items, 0..) |it, i| {
                if (g.hit(.{ .x = it.x, .y = it.y, .w = @intCast(it.ic.w), .h = @intCast(it.ic.h) })) {
                    self.drag = @intCast(i);
                    self.moved = false;
                    self.grab_dx = @intCast(@as(i32, g.px) - it.x);
                    self.grab_dy = @intCast(@as(i32, g.py) - it.y);
                    break;
                }
            }
        }

        // --- draw ---
        g.rect(.{ .x = 0, .y = 0, .w = sw, .h = 200 }, gui.DESK); // green work area
        for (self.items) |it| placeIcon(g, it.x, it.y, it.ic, it.label);
        if (self.menubar.process(g, &DESK_MENUS, sw, false)) |p| {
            if (p.menu == 3) action = if (p.item == 0) .res_low else .res_medium;
        }
        return action;
    }

    fn snap(self: *Desktop, di: u8) void {
        const it = &self.items[di];
        it.x = @divFloor(it.x + GRID / 2, GRID) * GRID;
        it.y = @divFloor(it.y + GRID / 2, GRID) * GRID;
        self.clamp(it);
    }
};

// Blit a 1bpp icon (bit set = black, clear = white) at (x,y) with a centred label.
fn placeIcon(g: *gui.Gui, x: i16, y: i16, ic: icons.Icon, label: []const u8) void {
    const rowbytes: usize = (@as(usize, ic.w) + 7) / 8;
    var row: u16 = 0;
    while (row < ic.h) : (row += 1) {
        var col: u16 = 0;
        while (col < ic.w) : (col += 1) {
            const byte = ic.bits[row * rowbytes + col / 8];
            const ink = (byte >> @intCast(7 - (col % 8))) & 1 != 0;
            g.fb.setPixelValue(@intCast(x + @as(i16, @intCast(col))), @intCast(y + @as(i16, @intCast(row))), if (ink) gui.BLACK else gui.WHITE);
        }
    }
    const lw: i16 = @as(i16, @intCast(label.len)) * 8;
    g.text(label, x + @divTrunc(@as(i16, @intCast(ic.w)) - lw, 2), y + @as(i16, @intCast(ic.h)) + 2, gui.WHITE, gui.DESK);
}
