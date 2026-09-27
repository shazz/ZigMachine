// --------------------------------------------------------------------------
// Call 21, $3D722..$3D75C (the model's d_title.title), resumable: the title
// tune (id 5, looped), the title loop $3D994 until FIRE (the hall of fame,
// then the title picture, 176 VBLs each, Space = the grey palette), silence,
// a new game $3ADDA, every spawn record revived $39062, the level select
// $39348, the level load $3B00A with its intro, the submap entered, fade in,
// flip, wait.
//
// The power-on path $3D6AC..$3D72C (boot) runs the same body behind its own
// prefix: clear the work buffers and the screens, the level-select flags,
// the RNG seed $38FF6, the live palette, flip, wait, the title tune, the
// title picture, flip, wait, then 176 VBLs of the title before the loop.
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");
const clock = @import("clock.zig");
const hud = @import("hud.zig");
const screen = @import("screen.zig");
const snd = @import("sound.zig");
const newgame = @import("newgame.zig");
const rick = @import("rick.zig");
const hof = @import("hof.zig");
const fade = @import("fade.zig");
const intro = @import("intro.zig");
const wc = @import("world_calls.zig");
const select = @import("select.zig");
const Status = fade.Status;

pub const Title = struct {
    pc: enum { boot_flip, boot_wait, boot_flip2, boot_wait2, boot_hold, fo1, fi1, hold1, fo2, flip, wait, fi2, hold2, sel, load, enter, fi, flip3, wait3, done } = .fo1,
    fade: fade.Fade = .{},
    hold: fade.Hold = .{},
    sel: select.LevelSelect = .{},
    load: intro.LoadLevel = .{},
    enter: wc.EnterSubmap = .{},

    /// Call 21 from the loop (Esc, the end of a game).
    pub fn start(self: *Title) void {
        self.* = .{};
        snd.play(5, 1);
        self.fade.start(true);
        self.pc = .fo1;
    }

    /// Power-on, $3D6AC: the game's own start-up (no TOS here: Super, the
    /// vectors and the IKBD commands are the machine's).
    pub fn boot(self: *Title) void {
        self.* = .{};
        newgame.startUp();
        self.pc = .boot_flip;
    }

    pub fn step(self: *Title) Status {
        while (true) {
            if (self.bootStep()) |s| {
                if (s == .yield) return .yield;
                continue;
            }
            if (self.loopStep()) |s| {
                if (s == .yield) return .yield;
                continue;
            }
            if (self.pc == .done) return .done;
            if (self.tailStep() == .yield) return .yield;
        }
    }

    /// $3D6E8..$3D720, the power-on prefix. null: not in it.
    fn bootStep(self: *Title) ?Status {
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

    /// $3D994, the title loop: until FIRE.
    fn loopStep(self: *Title) ?Status {
        switch (self.pc) {
            .fo1 => {
                if (self.fade.step() == .yield) return .yield;
                hof.screenDraw();
                self.fade.start(false);
                self.pc = .fi1;
            },
            .fi1, .fi2 => {
                if (self.fade.step() == .yield) return .yield;
                self.hold.start();
                self.pc = if (self.pc == .fi1) .hold1 else .hold2;
            },
            .hold1, .hold2 => {
                if (self.hold.step() == .yield) return .yield;
                if (self.hold.fired) return self.afterLoop();
                self.fade.start(true);
                self.pc = if (self.pc == .hold1) .fo2 else .fo1;
            },
            .fo2 => {
                if (self.fade.step() == .yield) return .yield;
                screen.titlePicture();
                self.pc = .flip;
            },
            .flip => {
                if (hud.flipBlocked()) return .yield;
                screen.flipD();
                self.pc = .wait;
            },
            .wait => {
                if (hud.waitBlocked()) return .yield;
                screen.waitD();
                self.fade.start(false);
                self.pc = .fi2;
            },
            else => return null,
        }
        return .done;
    }

    /// $3D730..$3D754: silence, a new game, the level select.
    fn afterLoop(self: *Title) Status {
        snd.off();
        newgame.newGame();
        newgame.reviveSpawns();
        m.ww(0x3B89A, 0); // $3B8A2: bonus off
        m.ww(F.GAME_COMPLETE, 0);
        hud.clearSlots();
        rick.reset();
        rick.flag();
        clock.work(3000);
        self.sel.start();
        self.pc = .sel;
        return .done;
    }

    fn tailStep(self: *Title) Status {
        switch (self.pc) {
            .sel => {
                if (self.sel.step() == .yield) return .yield;
                m.ww(F.LEVEL, m.rw(F.SEL_LEVEL));
                self.load.start();
                self.pc = .load;
            },
            .load => {
                if (self.load.step() == .yield) return .yield;
                self.enter.start(); // $3943A = $39444 + fade in
                self.pc = .enter;
            },
            .enter => {
                if (self.enter.step() == .yield) return .yield;
                self.fade.start(false);
                self.pc = .fi;
            },
            .fi => {
                if (self.fade.step() == .yield) return .yield;
                self.pc = .flip3;
            },
            .flip3 => {
                if (hud.flipBlocked()) return .yield;
                screen.flipD();
                self.pc = .wait3;
            },
            .wait3 => {
                if (hud.waitBlocked()) return .yield;
                screen.waitD();
                self.pc = .done;
            },
            else => self.pc = .done,
        }
        return .done;
    }
};
