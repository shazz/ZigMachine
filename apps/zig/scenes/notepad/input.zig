// --------------------------------------------------------------------------
// NOTEPAD's keyboard and mouse. Keys arrive through the cart's key() / input()
// exports (docs/sealed-loader.js KEY_CODES, glass's map.zig: the same codes on
// the board) and are queued, then handled in the frame, where drawing is allowed.
// Control is a key of its own (0xE014 / 0xE016, its release through keyUp): with
// it held a letter is a menu shortcut, as ^N ^O ^S ^Q ^X ^C ^V ^A ^F were on TOS.
// --------------------------------------------------------------------------
const rom = @import("rom_sdk");
const aes = rom.aes;
const menu = @import("menu.zig");
const flow = @import("flow.zig");
const App = @import("../notepad.zig").App;

pub const K_DELETE: u32 = 0xE00C;
pub const K_ESC: u32 = 0xE012;
pub const K_CTRL_L: u32 = 0xE014;
pub const K_SHIFT_L: u32 = 0xE015;
pub const K_CTRL_R: u32 = 0xE016;
pub const K_SHIFT_R: u32 = 0xE017;
pub const K_TAB: u32 = 0xE019;
pub const K_HOME: u32 = 0xE01A;
pub const K_END: u32 = 0xE01B;
pub const K_PGUP: u32 = 0xE01C;
pub const K_PGDN: u32 = 0xE01D;
/// The arrows (input(0..3)) queued among the keys, in the order they came.
pub const K_ARROW: u32 = 0xF000;

pub const Queue = struct {
    k: [32]u32 = undefined,
    n: u8 = 0,
    pub fn push(self: *Queue, cp: u32) void {
        if (self.n < self.k.len) {
            self.k[self.n] = cp;
            self.n += 1;
        }
    }
};

/// A key down: the modifiers at once, the rest queued for the frame.
pub fn down(a: *App, cp: u32) void {
    switch (cp) {
        K_CTRL_L, K_CTRL_R => a.ctrl = true,
        K_SHIFT_L, K_SHIFT_R => a.shift = true,
        else => a.keys.push(cp),
    }
}
pub fn up(a: *App, cp: u32) void {
    switch (cp) {
        K_CTRL_L, K_CTRL_R => a.ctrl = false,
        K_SHIFT_L, K_SHIFT_R => a.shift = false,
        else => {},
    }
}

/// The queued keys: to the open dialog, or to the text.
pub fn drain(a: *App) void {
    const n = a.keys.n;
    a.keys.n = 0;
    for (a.keys.k[0..n]) |cp| {
        if (a.modal != .none) modalKey(a, cp) else textKey(a, cp);
    }
}

fn modalKey(a: *App, cp: u32) void {
    switch (a.modal) {
        .find => a.find.key(cp),
        .fsel_open, .fsel_save => if (cp == 13) aes.key(a.g, cp) else a.fsel.key(cp),
        else => aes.key(a.g, cp), // Return fires the alert's default button
    }
}

// A control code a keyboard may send for ^letter (not Backspace, Tab, LF, Return).
fn isControl(cp: u32) bool {
    return cp >= 1 and cp <= 26 and cp != 8 and cp != 9 and cp != 10 and cp != 13;
}

fn textKey(a: *App, cp: u32) void {
    const d = &a.doc;
    const page = @max(1, a.view.rows -| 1);
    if (isControl(cp) or (a.ctrl and cp < 128 and ((cp | 0x20) >= 'a' and (cp | 0x20) <= 'z')))
        return flow.run(a, menu.ofKey(@intCast(cp)));
    switch (cp) {
        8 => d.backspace(),
        K_DELETE => d.deleteFwd(),
        13, 10 => d.typeChar('\n') catch |e| flow.full(a, e),
        K_TAB => d.typeChar('\t') catch |e| flow.full(a, e),
        K_HOME => d.home(a.shift),
        K_END => d.end(a.shift),
        K_PGUP => d.vertical(false, page, a.shift),
        K_PGDN => d.vertical(true, page, a.shift),
        K_ARROW + 0 => d.vertical(false, 1, a.shift),
        K_ARROW + 1 => d.vertical(true, 1, a.shift),
        K_ARROW + 2 => d.left(a.shift),
        K_ARROW + 3 => d.right(a.shift),
        K_ESC => d.moveTo(d.cursor, false),
        else => if ((cp >= 32 and cp < 127) or (cp >= 128 and cp < 256)) d.typeChar(@intCast(cp)) catch |e| flow.full(a, e),
    }
}

/// The pointer: a press in the text places the cursor (Shift extends), a drag selects.
pub fn press(a: *App) void {
    a.doc.moveTo(a.view.hit(&a.doc, a.px, a.py), a.shift);
    a.selecting = true;
}
pub fn drag(a: *App) void {
    if (!a.selecting) return;
    if (!a.down) {
        a.selecting = false;
        return;
    }
    const p = a.view.hit(&a.doc, a.px, a.py);
    if (p != a.doc.cursor) a.doc.moveTo(p, true);
}
