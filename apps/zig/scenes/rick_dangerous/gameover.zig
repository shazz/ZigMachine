// --------------------------------------------------------------------------
// Call 20, $3D850..$3D8B0 (the model's d_title.end_of_game), resumable:
// clear + HUD, tune 6, 'GAME OVER', fade in, wait while the tune plays, then
// up to 61 VBLs or FIRE, silence, the hall of fame insert and name entry.
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");
const clock = @import("clock.zig");
const hud = @import("hud.zig");
const screen = @import("screen.zig");
const snd = @import("sound.zig");
const hof = @import("hof.zig");
const fade = @import("fade.zig");
const Status = fade.Status;

pub const EndOfGame = struct {
    pc: enum { fi, tune, hold, insert, done } = .done,
    fade: fade.Fade = .{},
    insert: hof.Insert = .{},
    k: i64 = 0,

    pub fn start(self: *EndOfGame) void {
        self.* = .{};
        screen.clearHud();
        snd.play(6, 0);
        screen.printAt(0xF, 0xC, 0x3D8B4);
        screen.printAt(0x15, 0xC, 0x3D8B9);
        self.fade.start(false);
        self.pc = .fi;
    }

    pub fn step(self: *EndOfGame) Status {
        while (true) switch (self.pc) {
            .fi => {
                if (self.fade.step() == .yield) return .yield;
                self.pc = .tune;
            },
            .tune => { // wait while the tune plays
                if (hud.waitBlocked()) return .yield;
                screen.waitD();
                if (m.rw(F.MUSIC_BUSY) == 0) self.pc = .hold;
            },
            .hold => { // up to 61 VBLs, or FIRE
                if (self.k < 0x3D) {
                    if (hud.waitBlocked()) return .yield;
                    screen.waitD();
                    self.k += 1;
                    if (m.rb(F.JOY) & 0x80 == 0) continue;
                }
                snd.off();
                clock.work(400);
                self.insert.start();
                self.pc = .insert;
            },
            .insert => {
                if (self.insert.step() == .yield) return .yield;
                self.pc = .done;
            },
            .done => return .done,
        };
    }
};
