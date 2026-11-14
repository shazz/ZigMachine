// --------------------------------------------------------------------------
// SysInfo — the pointer. In low and medium the host draws it (the page's cursor,
// the board's arrow). In the desk nobody does (docs/GEM_DESK_MODE.md §4): the
// ROM draws TOS's ARROW into the plane at graf_mouse M_ON and puts the screen
// back at M_OFF, keeping what was under it in scratch the program lends
// (aes.lendScratch). Matt on the board, 14 Nov: "no mouse, hard to click".
//
// The arrow comes off only on a frame that draws (or moves it): taking it off
// and back every frame would rewrite it while the board scans the plane, the
// flash every GEM box had when it was repainted per frame. (An alert up takes it
// off and back each frame: the ROM's dialog may draw any frame, and it is brief.)
// --------------------------------------------------------------------------
const zg = @import("zigos");
const rom = @import("rom_sdk");
const aes = rom.aes;
const App = @import("../sysinfo.zig").App;

/// Lend the ROM the save-under for the arrow (and its other two, unused here).
pub fn lend(g: rom.Gui) void {
    const mem = zg.mem.mustAlloc(u8, aes.SCRATCH_BYTES + 4);
    const at = (4 - @intFromPtr(mem.ptr) % 4) % 4;
    _ = aes.lendScratch(g, @alignCast(mem[at..][0..aes.SCRATCH_BYTES]));
}

var last = [3]i32{ -1, -1, -1 };

/// The host's pointer: to the ROM (mapped to the mode), and the arrow due to move only when it
/// changed (a host may send it every frame).
pub fn host(app: *App, x: i32, y: i32, buttons: u32) void {
    aes.hostPointer(app.g, x, y, buttons);
    const now = [3]i32{ x, y, @intCast(buttons & 0xFF) };
    if (now[0] == last[0] and now[1] == last[1] and now[2] == last[2]) return;
    last = now;
    app.pointer_moved = true;
}

/// Will this frame draw, or move the arrow? `due`: the live values' refresh.
pub fn drawing(app: *const App, due: bool) bool {
    return app.pointer_moved or app.covered or app.dirty or due or app.dialog.active() or (app.menu_open and !app.menu_drawn);
}

/// graf_mouse(M_OFF) before the frame's first drawing.
pub fn off(app: *App) void {
    if (app.arrow_off) return;
    aes.mouse(app.g, false);
    app.arrow_off = true;
}

/// graf_mouse(M_ON) after its last: the arrow at the pointer, on top of what was drawn.
pub fn on(app: *App) void {
    if (!app.arrow_off) return;
    aes.mouse(app.g, true);
    app.arrow_off = false;
    app.pointer_moved = false;
}
