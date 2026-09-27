// --------------------------------------------------------------------------
// The power-on path $3D6AC..$3D72C (the model's d_title.boot): the game's
// start-up (clear the work buffers and the screens, the level-select flags,
// the RNG seed $38FF6, the live palette), flip, wait, the title tune, the
// title picture, flip, wait, then 176 VBLs of the title; then the title's
// own body (title.zig) from its loop, or straight to a new game on FIRE.
// --------------------------------------------------------------------------
const hud = @import("hud.zig");
const screen = @import("screen.zig");
const snd = @import("sound.zig");
const newgame = @import("newgame.zig");
const Title = @import("title.zig").Title;
const Status = @import("fade.zig").Status;

/// $3D6AC: the game's own start-up (no TOS here: Super, the vectors and the
/// IKBD commands are the machine's).
pub fn start(self: *Title) void {
    newgame.startUp();
    self.pc = .boot_flip;
}

/// $3D6E8..$3D720, the power-on prefix. null: not in it.
pub fn step(self: *Title) ?Status {
    switch (self.pc) {
        .boot_flip, .boot_flip2 => {
            if (hud.flipBlocked()) return .yield;
            screen.flipD();
            self.pc = if (self.pc == .boot_flip) .boot_wait else .boot_wait2;
        },
        .boot_wait => {
            if (hud.waitBlocked()) return .yield;
            screen.waitD();
            snd.play(5, 1);
            screen.titlePicture();
            self.pc = .boot_flip2;
        },
        .boot_wait2 => {
            if (hud.waitBlocked()) return .yield;
            screen.waitD();
            self.hold.start();
            self.pc = .boot_hold;
        },
        .boot_hold => {
            if (self.hold.step() == .yield) return .yield;
            if (self.hold.fired) return self.afterLoop();
            self.fade.start(true);
            self.pc = .fo1;
        },
        else => return null,
    }
    return .done;
}
