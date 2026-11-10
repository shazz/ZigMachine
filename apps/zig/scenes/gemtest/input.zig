// --------------------------------------------------------------------------
// GEMTEST's keyboard. Keys come through the cart's key() export (the page's and
// glass's codes, notepad/input.zig) and are queued, then handled in the frame,
// where drawing is allowed. Control is a key of its own (0xE014 / 0xE016, its
// release through keyUp): with it held a letter is a menu shortcut. Order: an
// open modal takes every key; then the shortcuts; then the top area (the Dialogs
// field's digits, Return); then 1 2 3 switch the screen mode.
// --------------------------------------------------------------------------
const rom = @import("rom_sdk");
const aes = rom.aes;
const menu = @import("menu.zig");
const flow = @import("flow.zig");
const areas = @import("areas.zig");
const App = @import("../gemtest.zig").App;

pub const K_CTRL_L: u32 = 0xE014;
pub const K_CTRL_R: u32 = 0xE016;

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

pub fn down(a: *App, cp: u32) void {
    if (cp == K_CTRL_L or cp == K_CTRL_R) a.ctrl = true else a.keys.push(cp);
}
pub fn up(a: *App, cp: u32) void {
    if (cp == K_CTRL_L or cp == K_CTRL_R) a.ctrl = false;
}

pub fn drain(a: *App) void {
    const n = a.keys.n;
    a.keys.n = 0;
    for (a.keys.k[0..n]) |cp| one(a, cp);
}

// A control code a keyboard may send for ^letter (not Backspace, Tab, LF, Return).
fn isControl(cp: u32) bool {
    return cp >= 1 and cp <= 26 and cp != 8 and cp != 9 and cp != 10 and cp != 13;
}

fn one(a: *App, cp: u32) void {
    switch (a.modal) {
        .none => {},
        .fsel => return if (cp == 13) aes.key(a.g, cp) else a.fsel.key(cp),
        else => return aes.key(a.g, cp), // Return fires the alert's default button
    }
    if (isControl(cp) or (a.ctrl and cp < 128 and (cp | 0x20) >= 'a' and (cp | 0x20) <= 'z'))
        return flow.run(a, menu.ofKey(@intCast(cp)), true);
    if (a.wins.area) |ar| if (a.wins.topSlot() != null and areas.key(a, ar, cp)) return;
    if (cp >= '1' and cp <= '3') a.setShadeMode(cp - '1');
}
