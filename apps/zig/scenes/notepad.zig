// --------------------------------------------------------------------------
// NOTEPAD: a windowed text editor for GEM 5 on KOS, written as a TOS program was,
// to VALIDATE GEM 5's program API (docs/NOTEPAD.md has what that turned up).
// Everything GEM is the ROM's, through rom_sdk: the window and its gadgets, the
// menu bar, form_alert, the ITEM SELECTOR, graf_mouse (aes.zig, table 1.17); the
// files are KOS GEMDOS's (C:\*.TXT). The program draws only its text, and only
// the rows that changed (notepad/view.zig): an idle frame paints nothing.
//
// A GEM program: BOOT.WSM on a data disk, double-clicked in the desktop; it opens
// in the desktop's resolution (low, medium or the 640x480 desk), Quit goes back.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const hw = @import("hardware");
const rom = @import("rom_sdk");
const aes = rom.aes;
const doc_mod = @import("notepad/doc.zig");
const View = @import("notepad/view.zig").View;
const Find = @import("notepad/find.zig").Find;
const menu = @import("notepad/menu.zig");
const flow = @import("notepad/flow.zig");
const inp = @import("notepad/input.zig");
const screen = @import("notepad/screen.zig");
const frame = @import("notepad/frame.zig");

const PLANE: u32 = 0;
pub const MAX_TEXT: usize = 64 * 1024;
pub const MAX_LINES: usize = 16384;
const IO_BYTES: usize = 2 * MAX_TEXT + 1; // a file with CR LF line ends, and the byte that says "longer"

pub const App = struct {
    fb: *zg.LogicalFB = undefined,
    g: rom.Gui = .{},
    dialog: rom.Dialog = .{},
    fsel: rom.FileSel = .{},
    bar: aes.MenuBar = undefined,
    view: View = undefined,
    doc: doc_mod.Doc = undefined,
    find: Find = .{},
    io: []u8 = &.{},
    mode: aes.ScreenMode = .medium,
    desk_ok: bool = false,
    name: [13]u8 = undefined,
    name_len: u8 = 0,
    modal: flow.Modal = .none,
    pending: menu.Cmd = .none,
    keys: inp.Queue = .{},
    ctrl: bool = false,
    shift: bool = false,
    px: i32 = 0,
    py: i32 = 0,
    down: bool = false,
    selecting: bool = false,
    repaint: bool = true,
    shown_title: u32 = 0xFFFF_FFFF,
    shown_edit: u8 = 0xFF,
    wants_quit: bool = false,

    pub fn init(self: *App, os: *zg.ZigOS) void {
        self.g.close(); // memory reused across a cart swap may hold stale handles (sysinfo's rule)
        self.dialog.close();
        self.fsel.close();
        self.* = .{};
        g_app = self;
        self.fb = &os.lfbs[PLANE];
        const mem = zg.mem.mustAlloc(u8, MAX_TEXT * 2 + IO_BYTES + aes.SCRATCH_BYTES + 4);
        const starts = zg.mem.mustAlloc(u32, MAX_LINES);
        self.doc = .{ .text = doc_mod.Text.init(mem[0..MAX_TEXT], starts[0..MAX_LINES]), .clip = mem[MAX_TEXT .. 2 * MAX_TEXT] };
        self.io = mem[2 * MAX_TEXT ..][0..IO_BYTES];
        self.desk_ok = screen.allocPlane(self.fb);
        self.mode = screen.boot(aes.screenMode(), self.desk_ok);
        screen.apply(self.fb, self.mode);
        self.g = rom.Gui.openPlane(PLANE, screen.width(self.mode), screen.height(self.mode));
        self.dialog = rom.Dialog.open();
        self.fsel = rom.FileSel.open();
        rom.installPalette(PLANE);
        os.setBackgroundColor(self.fb.getPaletteEntry(rom.WHITE));
        const scratch = mem[2 * MAX_TEXT + IO_BYTES ..];
        const at = (4 - @intFromPtr(scratch.ptr) % 4) % 4;
        _ = aes.lendScratch(self.g, @alignCast(scratch[at..][0..aes.SCRATCH_BYTES]));
        self.bar = .{ .g = self.g };
        _ = menu.build(self.bar);
        const win = aes.Window.open(self.g, screen.windowRect(self.mode), "") orelse return;
        self.view = .{ .g = self.g, .win = win };
        self.newText();
    }

    /// The window's title: the file's name, or UNTITLED.
    pub fn title(self: *const App) []const u8 {
        return if (self.name_len == 0) "UNTITLED" else self.name[0..self.name_len];
    }

    pub fn newText(self: *App) void {
        self.doc.text.clear();
        self.doc.reset();
        self.name_len = 0;
        self.view.top = 0;
        self.view.left = 0;
        self.view.widest = 0;
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
        self.down = buttons & 1 != 0;
    }
    pub fn key(self: *App, cp: u32) void {
        inp.down(self, cp);
    }
    pub fn input(self: *App, dir: u32) void {
        if (dir < 4) self.keys.push(inp.K_ARROW + dir);
    }
    /// Digits 1-3 (the harness, and the page's keys for a cart that does not own the keyboard):
    /// low, medium, the desk.
    pub fn setShadeMode(self: *App, m: u32) void {
        if (m > 2) return;
        const was = self.mode;
        self.mode = screen.switchTo(self.fb, @enumFromInt(m), self.desk_ok);
        self.g.resize(screen.width(self.mode), screen.height(self.mode));
        if (self.mode != was) self.view.win.set(screen.windowRect(self.mode)); // the same mode: the window stays
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
        aes.mouse(self.g, false); // graf_mouse(M_OFF): the desk's arrow comes off first
        defer aes.mouse(self.g, true);
        if (self.repaint) self.paintAll();
        if (self.modal != .none) self.view.draw(&self.doc); // a repaint under an open dialog: the text too, then the box over it
        inp.drain(self);
        if (self.modal != .none) return frame.modal(self);
        if (self.bar.process(false)) |p| flow.run(self, menu.ofPick(p));
        if (self.modal == .none and !self.bar.busy()) self.windowFrame();
        if (self.modal != .none or self.bar.busy()) return;
        self.view.absorb(&self.doc);
        self.view.sliders(&self.doc);
        frame.chrome(self);
        self.view.draw(&self.doc);
    }

    // The desk, the window and every row: at start, after a dialog, a move or a size.
    fn paintAll(self: *App) void {
        self.repaint = false;
        screen.desk(self.g, self.mode);
        self.view.win.draw();
        self.view.layout();
        self.bar.redraw();
        self.shown_title = 0xFFFF_FFFF;
    }

    fn windowFrame(self: *App) void {
        const ev = aes.processWindows(self.g);
        if (ev & aes.EV_CLOSED != 0) return flow.run(self, .quit);
        if (ev & (aes.EV_MOVED | aes.EV_SIZED) != 0) return self.paintAll();
        if (ev & aes.EV_SCROLLED != 0) self.view.scrolledTo(self.view.win.vscroll(), self.view.win.hscroll());
        if (ev & aes.EV_WORK != 0) inp.press(self) else inp.drag(self);
    }
};

const std = @import("std");

// keyUp: Control and Shift come up. demo_main forwards no release, so the cart exports its own
// (joust.zig's pattern), guarded so only NOTEPAD's cart carries it.
var g_app: ?*App = null;
fn keyUp(cp: u32) callconv(.c) void {
    inp.up(g_app orelse return, cp);
}
comptime {
    if (@import("../cart.zig").Cart == App) @export(&keyUp, .{ .name = "keyUp" });
}
