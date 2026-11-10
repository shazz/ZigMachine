// --------------------------------------------------------------------------
// GEM 5's program API, the app's half (the ROM's is rom/rom_app.zig): windows with
// their messages, a menu bar, form_alert, graf_mouse, Getrez. System table 1.17:
// a cart that calls these needs a ROM that has them (an older rom.wasm leaves the
// imports unresolved; the page's tolerant env stubs them to 0, so every call does
// nothing and winOpen returns 0: check it). Wrappers below; numbers only cross.
// --------------------------------------------------------------------------
const rom = @import("rom.zig");
const Rect = rom.Rect;
/// WM_REDRAW rectangle lists, the window stack, the clip (system table 1.22).
pub const redraw = @import("aes_redraw.zig");
/// Object trees in the program's memory: objc_draw / objc_find / form_button / objc_edit (1.23).
pub const obj = @import("aes_obj.zig");

pub extern fn guiKey(h: u32, cp: u32) void;
pub extern fn guiScratch(h: u32, ptr: u32, len: u32) u32;
pub extern fn guiHostPointer(h: u32, x: i32, y: i32, buttons: u32) void;
pub extern fn guiTextClip(h: u32, ptr: u32, len: u32, x: i32, y: i32, ink: u32, paper: u32, cx: i32, cy: i32, cw: i32, ch: i32) void;
pub extern fn guiCell(h: u32) u32;
pub extern fn guiMouse(h: u32, on: u32) void;
pub extern fn deskScreenMode() u32;
pub extern fn deskReturnMode() u32; // table 1.18 (rom/rom_deskmode.zig)
pub extern fn dialogFormAlert(h: u32, default: u32, ptr: u32, len: u32) u32;
pub extern fn dialogChoice(h: u32) u32;
pub extern fn fileSelSetName(h: u32, ptr: u32, len: u32) void;
pub extern fn fileSelSpec(h: u32, out: u32, out_cap: u32) u32; // system table 1.18
pub extern fn fileSelDrives(h: u32, map: u32) void; // system table 1.21 (rom_app_fsel.zig)
pub extern fn menuReset(h: u32) void;
pub extern fn menuTitle(h: u32, ptr: u32, len: u32) u32;
pub extern fn menuItem(h: u32, ptr: u32, len: u32, flags: u32) u32;
pub extern fn menuFlags(h: u32, m: u32, i: u32, flags: u32) u32;
pub extern fn menuProcess(h: u32, locked: u32) u32;
pub extern fn menuDraw(h: u32) void;
pub extern fn menuBusy(h: u32) u32;
pub extern fn winOpen(h: u32, x: i32, y: i32, w: i32, hh: i32, ptr: u32, len: u32) u32;
pub extern fn winClose(h: u32, id: u32) void;
pub extern fn winTitle(h: u32, id: u32, ptr: u32, len: u32) void;
pub extern fn winInfo(h: u32, id: u32, ptr: u32, len: u32) void;
pub extern fn winScroll(h: u32, id: u32, vertical: u32, size: i32, pos: i32, max: i32, page: i32) void;
pub extern fn winSet(h: u32, id: u32, x: i32, y: i32, w: i32, hh: i32) void;
pub extern fn winProcess(h: u32) u32;
pub extern fn winEvents(h: u32, id: u32) u32;
pub extern fn winDraw(h: u32, id: u32) void;
pub extern fn winDrawBars(h: u32, id: u32) void;
pub extern fn winGet(h: u32, id: u32, what: u32) i32;

fn p(s: []const u8) u32 {
    return @intCast(@intFromPtr(s.ptr));
}
fn n(s: []const u8) u32 {
    return @intCast(s.len);
}

/// The window events (winProcess / Window.events), the AES's messages as bits.
pub const EV_WORK: u32 = 1; // a press started in the top window's work area: the program's
pub const EV_HIT: u32 = 2; // a press on a window's gadgets: not the program's
pub const EV_CLOSED: u32 = 4; // WM_CLOSED: a request; the window stays until close()
pub const EV_MOVED: u32 = 8; // WM_MOVED (done)
pub const EV_SIZED: u32 = 16; // WM_SIZED / WM_FULLED (done)
pub const EV_SCROLLED: u32 = 32; // WM_ARROWED / WM_VSLID / WM_HSLID (done)
pub const EV_TOPPED: u32 = 64; // WM_TOPPED (done)

/// The desktop's screen when it launched this program (Getrez), null if no desktop ran.
pub const ScreenMode = enum(u8) { low = 0, medium = 1, desk = 2 };
pub fn screenMode() ?ScreenMode {
    const m = deskScreenMode();
    return if (m > 2) null else @enumFromInt(m);
}
/// The shell's start after a program quit: the mode the desktop launched it in (else null: a boot).
pub fn returnMode() ?ScreenMode {
    const m = deskReturnMode();
    return if (m > 2) null else @enumFromInt(m);
}

/// The scratch a program lends the ROM for its save-unders (rom_app.zig SCRATCH_BYTES, rounded up).
pub const SCRATCH_BYTES: usize = 44 * 1024;
/// Lend it (4-aligned, the program's own memory, kept for the whole run). False: refused.
pub fn lendScratch(g: rom.Gui, buf: []align(4) u8) bool {
    return guiScratch(g.h, p(buf), n(buf)) != 0;
}

/// Context-level calls the flat Gui wrapper lacks.
pub fn key(g: rom.Gui, cp: u32) void {
    guiKey(g.h, cp);
}
pub fn hostPointer(g: rom.Gui, x: i32, y: i32, buttons: u32) void {
    guiHostPointer(g.h, x, y, buttons);
}
pub fn textClip(g: rom.Gui, s: []const u8, x: i32, y: i32, ink: u8, paper: u8, clip: Rect) void {
    guiTextClip(g.h, p(s), n(s), x, y, ink, paper, clip.x, clip.y, clip.w, clip.h);
}
/// The system font's cell, [w, h].
pub fn cell(g: rom.Gui) [2]i16 {
    const c = guiCell(g.h);
    return .{ @intCast(c >> 16), @intCast(c & 0xFFFF) };
}
/// graf_mouse(M_OFF) before a frame's drawing, M_ON after (the desk's arrow; elsewhere a no-op).
pub fn mouse(g: rom.Gui, on: bool) void {
    guiMouse(g.h, @intFromBool(on));
}

/// form_alert: open it (false: the string is malformed); the button comes from choice().
pub fn formAlert(d: rom.Dialog, default: u32, spec: []const u8) bool {
    return dialogFormAlert(d.h, default, p(spec), n(spec)) != 0;
}
pub fn choice(d: rom.Dialog) u32 {
    return dialogChoice(d.h);
}
pub fn fileSelName(f: rom.FileSel, name: []const u8) void {
    fileSelSetName(f.h, p(name), n(name));
}
/// The selector's path spec (`C:\NET\*.TXT`) into `out`: the folder its list shows, then the mask.
/// After a `relist` answer, the program adds that folder's names (folders with a trailing `\`).
pub fn fileSelSpecOf(f: rom.FileSel, out: []u8) []const u8 {
    return out[0..fileSelSpec(f.h, p(out), n(out))];
}
/// The ITEM SELECTOR's DRIVE: buttons: the drives present (GEMDOS Dsetdrv's map, bit 0 = A:).
pub fn fileSelDrivesSet(f: rom.FileSel, map: u32) void {
    fileSelDrives(f.h, map);
}

pub const MENU_DISABLED: u32 = 1;
pub const MENU_CHECKED: u32 = 2;

/// A program's menu bar (menu_bar): titles then their items, a pick a frame.
pub const MenuBar = struct {
    g: rom.Gui,

    pub fn reset(self: MenuBar) void {
        menuReset(self.g.h);
    }
    pub fn title(self: MenuBar, s: []const u8) bool {
        return menuTitle(self.g.h, p(s), n(s)) != 0;
    }
    pub fn item(self: MenuBar, s: []const u8, fl: u32) bool {
        return menuItem(self.g.h, p(s), n(s), fl) != 0;
    }
    pub fn flags(self: MenuBar, m: u32, i: u32, f: u32) void {
        _ = menuFlags(self.g.h, m, i, f);
    }
    /// The pick this frame as {menu, item}, or null.
    pub fn process(self: MenuBar, locked: bool) ?[2]u8 {
        const r = menuProcess(self.g.h, @intFromBool(locked));
        if (r == 0) return null;
        return .{ @intCast((r - 1) >> 8), @intCast((r - 1) & 0xFF) };
    }
    pub fn redraw(self: MenuBar) void {
        menuDraw(self.g.h);
    }
    pub fn busy(self: MenuBar) bool {
        return menuBusy(self.g.h) != 0;
    }
};

pub const Window = @import("aes_window.zig").Window; // wind_create .. wind_get (aes_window.zig)
/// A frame of every window's input (winProcess): the OR of their EV_* bits.
pub fn processWindows(g: rom.Gui) u32 {
    return winProcess(g.h);
}
