// --------------------------------------------------------------------------
// GEMTEST: every GEM 5 component on one disk, to SEE them (and their bugs) on the
// board, in low, medium and the desk. A GEM program as NOTEPAD is: BOOT.WSM on a
// data disk, double-clicked in the desktop, opened in the desktop's resolution,
// ^Q back. It uses ONLY the program API (rom_sdk + rom_sdk.aes); what that lacks
// is shown as a grey "not in the API yet" line (docs/GEMTEST.md has the list).
//
// The Test menu (or ^W ^E ^D ^A ^F ^T ^I ^R) shows an area's window: Windows (four,
// every gadget, overlapping, one larger than the screen), Menus, Dialogs, Alerts,
// File selector, Text and fonts, Icons, Screen modes. Keys 1 2 3 switch the mode.
// gemtestShow(id) opens a component for apps/gemtest_shots.mjs (ids in docs/GEMTEST.md).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const rom = @import("rom_sdk");
const aes = rom.aes;
const menu = @import("gemtest/menu.zig");
const wins = @import("gemtest/wins.zig");
const flow = @import("gemtest/flow.zig");
const areas = @import("gemtest/areas.zig");
const inp = @import("gemtest/input.zig");
const dialogs = @import("gemtest/area_dialogs.zig");
const screen = @import("notepad/screen.zig");
const pen = @import("gemtest/pen.zig");

const PLANE: u32 = 0;

pub const App = struct {
    fb: *zg.LogicalFB = undefined,
    g: rom.Gui = .{},
    dialog: rom.Dialog = .{},
    fsel: rom.FileSel = .{},
    bar: aes.MenuBar = undefined,
    wins: wins.Set = .{},
    mode: aes.ScreenMode = .medium,
    boot_mode: ?aes.ScreenMode = null,
    desk_ok: bool = false,
    modal: flow.Modal = .none,
    keys: inp.Queue = .{},
    ctrl: bool = false,
    px: i32 = 0,
    py: i32 = 0,
    repaint: bool = true,
    wants_quit: bool = false,
    pending: u8 = 0, // gemtestShow's component, opened at the next frame
    dlg: dialogs.State = .{},
    check1: bool = true,
    check2: bool = false,
    last_pick: []const u8 = "none",
    picks: u16 = 0,
    shortcuts: u16 = 0,
    alert_last: u8 = 0xFF,
    alert_choice: u32 = 0,
    alert_ok: bool = false,
    fs: flow.FileState = .{},

    pub fn init(self: *App, os: *zg.ZigOS) void {
        self.g.close(); // memory reused across a cart swap may hold stale handles (sysinfo's rule)
        self.dialog.close();
        self.fsel.close();
        self.* = .{};
        g_app = self;
        self.fb = &os.lfbs[PLANE];
        const scratch = zg.mem.mustAlloc(u8, aes.SCRATCH_BYTES + 4);
        self.desk_ok = screen.allocPlane(self.fb);
        self.boot_mode = aes.screenMode();
        self.mode = screen.boot(self.boot_mode, self.desk_ok);
        screen.apply(self.fb, self.mode);
        self.g = rom.Gui.openPlane(PLANE, screen.width(self.mode), screen.height(self.mode));
        self.dialog = rom.Dialog.open();
        self.fsel = rom.FileSel.open();
        rom.installPalette(PLANE);
        os.setBackgroundColor(self.fb.getPaletteEntry(rom.WHITE));
        const at = (4 - @intFromPtr(scratch.ptr) % 4) % 4;
        _ = aes.lendScratch(self.g, @alignCast(scratch[at..][0..aes.SCRATCH_BYTES]));
        self.bar = .{ .g = self.g };
        _ = menu.build(self.bar);
        self.syncMenu();
        self.showArea(.windows);
    }

    pub fn lastPick(self: *const App) []const u8 {
        return self.last_pick;
    }
    pub fn syncMenu(self: *App) void {
        menu.checks(self.bar, self.check1, self.check2, @intFromEnum(self.mode), self.desk_ok);
    }
    pub fn showArea(self: *App, a: areas.Area) void {
        self.wins.show(self.g, a, self.mode);
        self.repaint = true;
    }

    pub fn ownsKeyboard(self: *App) u32 {
        _ = self;
        return 1;
    }
    pub fn pollCart(self: *App) i32 {
        return if (self.wants_quit) 4 else 0; // 4: back to the desktop
    }
    pub fn pointer(self: *App, x: i32, y: i32, buttons: u32) void {
        aes.hostPointer(self.g, x, y, buttons);
        if (buttons & 2 != 0) return; // the page's double-click pulse is not a press
        self.px = if (self.mode == .low) @divTrunc(x, 2) else x;
        self.py = y;
    }
    pub fn key(self: *App, cp: u32) void {
        inp.down(self, cp);
    }
    /// 0 low, 1 medium, 2 the desk (keys 1 2 3, the Mode menu, the harness): the area is laid
    /// out again for the new screen.
    pub fn setShadeMode(self: *App, m: u32) void {
        if (m > 2) return;
        const was = self.mode;
        self.mode = screen.switchTo(self.fb, @enumFromInt(m), self.desk_ok);
        self.g.resize(screen.width(self.mode), screen.height(self.mode));
        if (self.mode != was) if (self.wins.area) |a| self.wins.show(self.g, a, self.mode); // the same mode: a repaint
        self.syncMenu();
        self.repaint = true;
    }

    pub fn update(self: *App, os: *zg.ZigOS, dt: f32) void {
        _ = os;
        _ = dt;
        self.g.beginFrame();
    }

    pub fn render(self: *App, os: *zg.ZigOS, dt: f32) void {
        _ = os;
        _ = dt;
        defer self.g.endFrame();
        aes.mouse(self.g, false); // graf_mouse(M_OFF) first, M_ON after (the desk's arrow)
        defer aes.mouse(self.g, true);
        if (self.pending != 0) self.openPending();
        if (self.repaint) {
            self.repaint = false;
            wins.paintAll(self);
        }
        inp.drain(self);
        if (self.modal != .none) return self.modalFrame();
        if (self.bar.process(false)) |p| flow.run(self, menu.ofPick(p), false);
        if (self.modal != .none or self.bar.busy()) return;
        if (wins.frame(self)) self.press();
    }

    fn modalFrame(self: *App) void {
        const r: rom.Result = if (self.modal == .fsel) self.fsel.process(self.g) else self.dialog.process(self.g);
        if (r != .none) flow.answered(self, r);
    }

    // A press in the top window's work area: the control under it, by the layout that drew it.
    fn press(self: *App) void {
        const t = self.wins.topSlot() orelse return;
        const a = self.wins.area orelse return;
        var p = pen.Pen.init(self.g, self.wins.slots[t].win.work(), self.wins.slots[t].top, self.wins.slots[t].left);
        p.drawing = false;
        p.hx = self.px;
        p.hy = self.py;
        areas.draw(&p, self, a, t);
        if (p.hit != pen.NONE) areas.press(self, a, p.hit);
    }

    // gemtestShow's component: 1..8 an area, 10..22 an alert over the Alerts area, 30..32 the
    // ITEM SELECTOR on A:\*.*, C:\*.*, C:\*.TXT over the File selector area.
    fn openPending(self: *App) void {
        const id = self.pending;
        self.pending = 0;
        if (self.modal != .none) return;
        switch (id) {
            1...8 => self.showArea(@enumFromInt(id)),
            10...22 => {
                self.showArea(.alerts);
                flow.alert(self, id - 10);
            },
            30...32 => {
                self.showArea(.files);
                flow.selector(self, id - 30);
            },
            else => {},
        }
    }
};

// keyUp (Control comes up) and gemtestShow, exported only by GEMTEST's cart (notepad's pattern).
var g_app: ?*App = null;
fn keyUp(cp: u32) callconv(.c) void {
    inp.up(g_app orelse return, cp);
}
fn gemtestShow(id: u32) callconv(.c) void {
    const a = g_app orelse return;
    a.pending = @intCast(@min(id, 255));
}
comptime {
    if (@import("../cart.zig").Cart == App) {
        @export(&keyUp, .{ .name = "keyUp" });
        @export(&gemtestShow, .{ .name = "gemtestShow" });
    }
}
