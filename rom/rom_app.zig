// --------------------------------------------------------------------------
// GEM 5's PROGRAM API: what a windowed GEM application needs from the ROM that the
// flat ABI of Phase 2 lacked (found writing NOTEPAD, docs/NOTEPAD.md). Appended
// exports (system table 1.17), the app's half is rom/sdk/aes.zig.
//
//   windows    win*: the desktop's window manager per program context, its gadgets'
//              results as event bits (WM_* messages), the outline drawn save-under
//   menu bar   menu*: titles and items copied in, drawn only when they change, the
//              screen under a drop-down saved and restored (TOS's AES did)
//   form_alert dialogFormAlert + dialogChoice: the AES's "[2][lines][Yes|No|Cancel]"
//   the rest   guiKey (Return fires a dialog's default button), guiHostPointer (the
//              host's pointer mapped to the mode, as the desktop's), guiTextClip,
//              guiCell (the font's cell), guiMouse (graf_mouse: the arrow where no
//              host draws one, the desk), fileSelSetName, deskScreenMode (Getrez)
//
// Handles are rom_main.zig's: every call on a bad one does nothing.
// --------------------------------------------------------------------------
const main = @import("rom_main.zig");
comptime {
    _ = @import("rom_app_win.zig"); // the window calls (win*)
    _ = @import("rom_app_fsel.zig"); // the ITEM SELECTOR's folders (fileSelSpec, 1.18)
}
const hw = @import("hardware");
const gui = @import("rom").gui;
const arrow = @import("rom").gem.deskarrow;
const appwin = gui.appwin;
const appmenu = gui.appmenu;
const saveunder = gui.saveunder;

// ONE program's worth: a wasm module that imports its memory ships its statics as data, so a
// set per context would put the desktop's unused share on every card. The first context to
// call one of these owns it until guiOpenPlane hands its slot out again.
pub var app_win: appwin.AppWin = undefined;
var app_bar: appmenu.AppMenu = undefined;
var app_mouse: Mouse = undefined;
var owner: ?usize = null;

const Mouse = struct { under: saveunder.Box = .{} };

/// guiOpenPlane gave out slot `i`: whatever the last program left in it is gone, its lent
/// scratch first (that address is the next program's memory now).
pub fn resetSlot(i: usize) void {
    if (owner != null and owner != i) return;
    app_win.reset();
    app_win.outline = .{};
    app_bar.reset();
    app_bar.under = .{};
    app_mouse = .{};
    owner = null;
}

/// The context's screen changed (guiResize): what the save-unders kept belongs to the old one.
pub fn screenChanged(i: usize) void {
    if (owner != i) return;
    app_mouse.under.at = null;
    app_win.outline.at = null;
    app_bar.under.at = null;
    app_bar.shown_open = -1;
    app_bar.must = true;
}

const MOUSE_BYTES = 16 * 16;
const OUTLINE_BYTES = appwin.OUTLINE_DOTS * 5;
/// The scratch a program lends for the save-unders: the arrow, a window outline, a drop-down.
pub const SCRATCH_BYTES = MOUSE_BYTES + OUTLINE_BYTES + appmenu.SAVE_BYTES;

/// Lend the ROM `len` bytes at `ptr` (4-aligned, in the cart's window) for the screen under
/// the arrow, a move/size outline and a drop-down (SCRATCH_BYTES: 42,656). The ROM keeps no
/// such buffer itself: a wasm module that imports its memory ships its zeros as data, and the
/// ROM is paid for on every card. Returns 1, or 0 (nothing lent) for a buffer too small or
/// outside the cart's window. Without one the three are drawn with nothing kept under them.
export fn guiScratch(h: u32, ptr: u32, len: u32) u32 {
    _ = slot(h) orelse return 0;
    const lo: u64 = ptr;
    if (ptr & 3 != 0 or len < SCRATCH_BYTES or lo < hw.CART_RAM_BASE or lo + len > hw.CART_RAM_TOP) return 0;
    const mem: [*]u8 = @ptrFromInt(ptr);
    const dots = appwin.OUTLINE_DOTS;
    app_mouse.under = .{ .buf = mem[0..MOUSE_BYTES] };
    const off: [*]u32 = @ptrCast(@alignCast(mem + MOUSE_BYTES));
    app_win.outline = .{ .off = off[0..dots], .old = mem[MOUSE_BYTES + dots * 4 ..][0..dots] };
    app_bar.under = .{ .buf = mem[MOUSE_BYTES + OUTLINE_BYTES ..][0..appmenu.SAVE_BYTES] };
    return 1;
}

pub fn slot(h: u32) ?usize {
    _ = main.guiAt(h) orelse return null;
    if (owner == null) {
        owner = h - 1;
        resetSlot(h - 1);
        owner = h - 1;
    }
    return if (owner == h - 1) h - 1 else null;
}

// --- input -------------------------------------------------------------------

/// A key the program read: Return / Enter fire the open dialog's default button.
export fn guiKey(h: u32, cp: u32) void {
    const g = main.guiAt(h) orelse return;
    if (cp == 13 or cp == 10) g.enter = true;
}
/// The host's pointer as it arrives (0..639 in every mode, bit 1 the page's double-click
/// pulse): mapped to the context's screen as the desktop maps its own (Screen.fromHost).
/// The pulse is not a press: it is dropped.
export fn guiHostPointer(h: u32, x: i32, y: i32, buttons: u32) void {
    const g = main.guiAt(h) orelse return;
    if (buttons & 2 != 0) return;
    const p = g.screen.fromHost(x, y);
    g.setPointer(p[0], p[1], buttons & 1);
}

// --- drawing -----------------------------------------------------------------

/// Text clipped per pixel to (cx, cy, cw, ch): a window's last, partly hidden column.
export fn guiTextClip(h: u32, ptr: u32, len: u32, x: i32, y: i32, ink: u32, paper: u32, cx: i32, cy: i32, cw: i32, ch: i32) void {
    const g = main.guiAt(h) orelse return;
    g.textClipped(main.slice(ptr, len), main.i16Of(x), main.i16Of(y), main.u8Of(ink), main.u8Of(paper), main.rectOf(cx, cy, cw, ch));
}
/// The system font's cell: width << 16 | height (8 x 8 in every mode of the repo's ROM).
export fn guiCell(h: u32) u32 {
    const g = main.guiAt(h) orelse return 0;
    const f = g.screen.font;
    return @as(u32, @intCast(f.cell_w)) << 16 | @as(u32, @intCast(f.cell_h));
}
/// graf_mouse M_OFF (0) / M_ON (1): in the desk no host draws the arrow (docs/GEM_DESK_MODE.md
/// §4), so the ROM draws TOS's ARROW at the pointer with the screen under it kept, and puts it
/// back at M_OFF. Call M_OFF before drawing a frame and M_ON after. Low and medium: nothing.
export fn guiMouse(h: u32, on: u32) void {
    _ = slot(h) orelse return;
    const g = main.guiAt(h).?;
    const m = &app_mouse;
    const p = saveunder.Plane{ .pix = g.fb.fb, .stride = g.fb.stride, .w = g.screen.w, .h = g.screen.h };
    m.under.restore(p);
    if (on == 0 or g.screen.mode != .desk) return;
    const at = arrow.at(g.px, g.py, g.screen.w, g.screen.h);
    _ = m.under.save(p, .{ .x = at[0], .y = at[1], .w = 16, .h = 16 });
    arrow.draw(.{ .pix = g.fb.fb, .stride = g.fb.stride, .w = g.screen.w, .h = g.screen.h }, at[0], at[1], .{ .mask = gui.WHITE, .data = gui.BLACK });
}
/// Getrez for a program GEM launched: the desktop's screen when it ran (0 low, 1 medium, 2 the
/// desk), 0xFF when no desktop ran on this machine since power-on (a cart booted directly).
/// The machine's RESOLUTION cannot say: every cart swap resets it (hwInit).
export fn deskScreenMode() u32 {
    if (!main.desk_seen) return 0xFF;
    return @intFromEnum(main.desk.g.screen.mode);
}

// --- form_alert, fsel_input's initial name ------------------------------------

/// form_alert(default, spec): 1 opened, 0 a malformed spec (nothing opened). Read the button
/// with dialogChoice after dialogProcess answers ok.
export fn dialogFormAlert(h: u32, default: u32, ptr: u32, len: u32) u32 {
    const d = main.dialogAt(h) orelse return 0;
    return @intFromBool(d.formAlert(main.slice(ptr, len), main.u8Of(default)));
}
/// The button (1-based, as form_alert returns it) that closed the last form_alert; 0 none.
export fn dialogChoice(h: u32) u32 {
    const d = main.dialogAt(h) orelse return 0;
    return d.choice;
}
/// The ITEM SELECTOR's Selection field before it shows (fsel_input's initial name).
export fn fileSelSetName(h: u32, ptr: u32, len: u32) void {
    const f = main.fselAt(h) orelse return;
    f.name.set(main.slice(ptr, len));
}

// --- the menu bar --------------------------------------------------------------

fn menuOf(h: u32) ?*appmenu.AppMenu {
    _ = slot(h) orelse return null;
    return &app_bar;
}

export fn menuReset(h: u32) void {
    (menuOf(h) orelse return).reset();
}
export fn menuTitle(h: u32, ptr: u32, len: u32) u32 {
    return @intFromBool((menuOf(h) orelse return 0).title(main.slice(ptr, len)));
}
export fn menuItem(h: u32, ptr: u32, len: u32, flags: u32) u32 {
    return @intFromBool((menuOf(h) orelse return 0).item(main.slice(ptr, len), flags));
}
/// menu_ienable / menu_icheck: flags bit 0 disabled, bit 1 checked.
export fn menuFlags(h: u32, m: u32, i: u32, flags: u32) u32 {
    return @intFromBool((menuOf(h) orelse return 0).setFlags(m, i, flags));
}
/// A frame of the bar: (menu << 8 | item) + 1 for a pick, 0 none. `locked`: a dialog is up.
export fn menuProcess(h: u32, locked: u32) u32 {
    const m = menuOf(h) orelse return 0;
    return m.process(main.guiAt(h).?, locked != 0);
}
/// Paint the bar at the next menuProcess (the screen under it was redrawn).
export fn menuDraw(h: u32) void {
    (menuOf(h) orelse return).must = true;
}
/// A drop-down is open: the pointer and the screen under it are the menu's.
export fn menuBusy(h: u32) u32 {
    return @intFromBool((menuOf(h) orelse return 0).busy());
}
