// --------------------------------------------------------------------------
// The resumable building blocks of the long calls. A task's step() runs
// until it is done, or until it must WAIT for a VBL the host's time has not
// reached (game.ahead): it then returns .yield and resumes at the same wait on
// a later host frame. start() does what the routine does before its first
// wait. The headless harness never yields: lockstep runs every task through.
//
//   Fade        $38E80 / $38E16: 8 x (wait; the colour registers one step)
//   SpaceToggle $3D8EA: Space: fade out, the other palette, fade in
//   Hold        the title's 176 x (wait; Space; FIRE leaves)
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");
const clock = @import("clock.zig");
const hud = @import("hud.zig");
const screen = @import("screen.zig");

pub const Status = enum { done, yield };

pub const Fade = struct {
    out: bool = true,
    k: i64 = 0,

    pub fn start(self: *Fade, out: bool) void {
        self.* = .{ .out = out };
        clock.work(if (out) clock.FADE_OUT_ENTRY else clock.FADE_IN_ENTRY);
    }

    pub fn step(self: *Fade) Status {
        while (self.k < 8) : (self.k += 1) {
            if (hud.waitBlocked()) return .yield;
            screen.waitD();
            if (self.out) screen.fadeOutStep(self.k == 7) else screen.fadeInStep(7 - self.k);
        }
        return .done;
    }
};

pub const SpaceToggle = struct {
    pc: enum { test_, out, in_, done } = .test_,
    fade: Fade = .{},

    pub fn start(self: *SpaceToggle) void {
        self.* = .{};
    }

    pub fn step(self: *SpaceToggle) Status {
        while (true) switch (self.pc) {
            .test_ => {
                clock.poll();
                if (m.rb(F.KEY) != 0x39) {
                    clock.work(36);
                    self.pc = .done;
                    continue;
                }
                self.fade.start(true);
                self.pc = .out;
            },
            .out => {
                if (self.fade.step() == .yield) return .yield;
                screen.swapPalette();
                self.fade.start(false);
                self.pc = .in_;
            },
            .in_ => {
                if (self.fade.step() == .yield) return .yield;
                self.pc = .done;
            },
            .done => return .done,
        };
    }
};

/// 176 x (wait; Space toggle; FIRE -> leave; work 40). fired says how it ended.
pub const Hold = struct {
    k: i64 = 0,
    in_toggle: bool = false,
    toggle: SpaceToggle = .{},
    fired: bool = false,

    pub fn start(self: *Hold) void {
        self.* = .{};
    }

    pub fn step(self: *Hold) Status {
        while (self.k < 0xB0) {
            if (!self.in_toggle) {
                if (hud.waitBlocked()) return .yield;
                screen.waitD();
                self.toggle.start();
                self.in_toggle = true;
            }
            if (self.toggle.step() == .yield) return .yield;
            self.in_toggle = false;
            if (m.rb(F.JOY) & 0x80 != 0) {
                self.fired = true;
                return .done;
            }
            clock.work(40);
            self.k += 1;
        }
        return .done;
    }
};
