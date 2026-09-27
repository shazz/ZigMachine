// --------------------------------------------------------------------------
// Call 17, the submap exit $394A2 and its level end $39512..$39592 (the
// model's a_level.py), resumable.
//
// Rick at x <= 0 or >= $E8: the exit record of the current submap on that
// side whose row is 0..2 below Rick's; found: the submap = its target and
// map_row -= row - newrow; Rick x = 2 (right) or $E6; not found: the SAME
// submap is entered again. Target -1: the next level (the intro screen, which
// waits for FIRE), or the game completed (the loop then leaves to $3D850).
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");
const hit = @import("hit.zig");
const fade = @import("fade.zig");
const intro = @import("intro.zig");
const wc = @import("world_calls.zig");
const Status = fade.Status;

const RICK_X: i64 = 0x3A1D4;
const RICK_Y: i64 = 0x3A1D6;

pub const SubmapExit = struct {
    pc: enum { enter, fo, load, enter2, fi, done } = .enter,
    enter: wc.EnterSubmap = .{},
    fade: fade.Fade = .{},
    load: intro.LoadLevel = .{},

    pub fn start(self: *SubmapExit) void {
        self.pc = .enter;
        const d0 = ((m.rw(RICK_Y) >> 3) + m.rw(F.MAP_ROW)) & 0xFFFF;
        const d2: i64 = if (m.s16(m.rw(RICK_X)) > 0) 1 else 0;
        if (findExit(d0, d2)) |a0| {
            m.wl(F.SUBMAP, m.rl(a0 + 4));
            if (m.rl(a0 + 4) == 0xFFFFFFFF) return self.nextLevel();
            const d = (m.rw(a0 + 2) - m.rw(a0 + 8)) & 0xFFFF;
            m.ww(F.MAP_ROW, m.rw(F.MAP_ROW) - d);
        }
        m.ww(RICK_X, if (d2 != 0) 2 else 0xE6);
        self.enter.start();
    }

    /// $39512: raise the level-select ceiling, level + 1; after level 4
    /// started from level 1: + 100000 per life (lives + 1 times) and the
    /// level-4 text; from a later level: a fade-out only. Either way
    /// game_complete = $FF.
    fn nextLevel(self: *SubmapExit) void {
        if (m.rw(F.MAX_LEVEL) != 3) {
            const d0 = (m.rw(F.LEVEL) + 1) & 0xFFFF;
            if (!(m.s16(d0) < m.s16(m.rw(F.MAX_LEVEL)))) m.ww(F.MAX_LEVEL, d0);
        }
        m.ww(F.LEVEL, m.rw(F.LEVEL) + 1);
        const done4 = m.s16(m.rw(F.LEVEL)) >= 4;
        if (done4 and m.rw(F.SEL_LEVEL) != 0) {
            self.fade.start(true);
            self.pc = .fo;
            return;
        }
        if (done4) {
            var n = m.rb(F.LIVES) + 1;
            while (n > 0) : (n -= 1) hit.scoreAdd(0x100000);
        }
        self.load.start();
        self.pc = .load;
    }

    pub fn step(self: *SubmapExit) Status {
        while (true) switch (self.pc) {
            .enter => {
                if (self.enter.step() == .yield) return .yield;
                self.pc = .done;
            },
            .fo => {
                if (self.fade.step() == .yield) return .yield;
                m.ww(F.GAME_COMPLETE, 0xFF);
                self.pc = .done;
            },
            .load => {
                if (self.load.step() == .yield) return .yield;
                if (m.s16(m.rw(F.LEVEL)) >= 4) {
                    m.ww(F.GAME_COMPLETE, 0xFF);
                    self.pc = .done;
                    continue;
                }
                self.enter.start(); // $395C2: x from the level record
                self.pc = .enter2;
            },
            .enter2 => {
                if (self.enter.step() == .yield) return .yield;
                self.fade.start(false);
                self.pc = .fi;
            },
            .fi => {
                if (self.fade.step() == .yield) return .yield;
                self.pc = .done;
            },
            .done => return .done,
        };
    }
};

/// The exit of the current submap on side d2 whose row is 0..2 below d0.
fn findExit(d0: i64, d2: i64) ?i64 {
    var a0 = m.rl(m.rl(F.SUBMAP) + 6);
    while (true) : (a0 += 10) {
        const d3 = m.rw(a0);
        if (d3 == 0xFF) return null;
        const dr = m.s16(d0 - m.rw(a0 + 2));
        if (d3 == d2 and 0 <= dr and dr <= 2) return a0;
    }
}
