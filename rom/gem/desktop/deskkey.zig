// --------------------------------------------------------------------------
// The desktop's keyboard (Desktop.key / Desktop.input). The name fields take printable keys,
// Backspace and Return (Show Info / New Folder, NAME CONFLICT); Return fires an open dialog's
// default button (TOS form_do). Control is a key of its own (0xE014 / 0xE016, as the page and
// the board's glass send it): held, a drag MOVES instead of copying (TOS). Its release comes
// from the shell's keyUp as the same code with RELEASE set (deskKey has one argument).
// --------------------------------------------------------------------------
const dt = @import("desktop.zig");
const deskdirty = @import("deskdirty.zig");
const Desktop = dt.Desktop;

pub const K_CTRL_L: u32 = 0xE014;
pub const K_CTRL_R: u32 = 0xE016;
const RELEASE = @import("../../sdk/deskop.zig").KEY_RELEASE; // the shell's keyUp

pub fn key(d: *Desktop, cp: u32) void {
    const code = cp & ~RELEASE;
    if (code == K_CTRL_L or code == K_CTRL_R) {
        d.fop.ctrl = cp & RELEASE == 0;
        return;
    }
    if (cp & RELEASE != 0) return;
    deskdirty.touch(d);
    if (d.fop.conflict.active) return d.fop.conflict.key(cp);
    if (d.info.active) return d.info.key(cp); // its name field takes Return itself
    if ((cp == 13 or cp == 10) and d.isModal() and !d.no_enter) d.g.enter = true; // the DEFAULT button (TOS form_do)
}

// Directional input (0 up 1 down 2 left 3 right): left/right walk a name field's caret.
pub fn input(d: *Desktop, dir: u32) void {
    deskdirty.touch(d);
    const delta: i8 = switch (dir) {
        2 => -1,
        3 => 1,
        else => return,
    };
    if (d.fop.conflict.active) return d.fop.conflict.moveCaret(delta);
    if (d.info.active) d.info.moveCaret(delta);
}
