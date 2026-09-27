// --------------------------------------------------------------------------
// The level select $39348 (the model's d_title.level_select), resumable:
// only when the flag $39346 and the ceiling $39344 are set; 'SELECT LEVEL',
// one line per level up to the ceiling; the cursor moves every 4 VBLs (it is
// printed in column 8, the entries' column); FIRE picks.
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");
const hud = @import("hud.zig");
const screen = @import("screen.zig");
const hof = @import("hof.zig");
const fade = @import("fade.zig");
const Status = fade.Status;

pub const LevelSelect = struct {
    pc: enum { fo, wait1, fi, cursor, waits, done } = .done,
    fade: fade.Fade = .{},
    d1: i64 = 9,
    d2: i64 = 0,
    w: u8 = 0,

    pub fn start(self: *LevelSelect) void {
        self.* = .{};
        m.ww(F.SEL_LEVEL, 0);
        if (m.rw(F.LEVEL_SELECT_ON) == 0 or m.rw(F.MAX_LEVEL) == 0) return;
        self.fade.start(true);
        self.pc = .fo;
    }

    pub fn step(self: *LevelSelect) Status {
        while (true) switch (self.pc) {
            .fo, .fi => {
                if (self.fade.step() == .yield) return .yield;
                self.pc = if (self.pc == .fo) .wait1 else .cursor;
            },
            .wait1 => {
                if (hud.waitBlocked()) return .yield;
                screen.waitD();
                entries();
                self.fade.start(false);
                self.pc = .fi;
            },
            .cursor => {
                screen.printAt(8, self.d1, hof.CURSOR);
                self.w = 0;
                self.pc = .waits;
            },
            .waits => {
                while (self.w < 4) : (self.w += 1) {
                    if (hud.waitBlocked()) return .yield;
                    screen.waitD();
                }
                self.pick();
            },
            .done => return .done,
        };
    }

    /// After the 4 waits: FIRE picks the level, else the cursor moves.
    fn pick(self: *LevelSelect) void {
        if (m.rb(F.JOY) & 0x80 != 0) {
            m.ww(F.SEL_LEVEL, self.d2);
            self.pc = .done;
            return;
        }
        screen.printAt(8, self.d1, hof.BLANK);
        self.move();
        self.pc = .cursor;
    }

    fn move(self: *LevelSelect) void {
        const j = m.rb(F.JOY);
        if (j & 1 != 0) {
            self.d2 -= 1;
            self.d1 -= 3;
            if (self.d2 < 0) {
                self.d2 = 0;
                self.d1 = 9;
            }
        } else if (j & 2 != 0) {
            self.d2 += 1;
            self.d1 += 3;
            if (self.d2 > m.s16(m.rw(F.MAX_LEVEL))) {
                self.d2 -= 1;
                self.d1 -= 3;
            }
        }
    }
};

/// Clear, the banner, one line per level up to the ceiling.
fn entries() void {
    screen.clearBoth();
    screen.banner(0x33270);
    var d1: i64 = 8;
    var k: i64 = 0;
    while (k < m.rw(F.MAX_LEVEL) + 1) : (k += 1) {
        screen.printAt(8, d1, 0x392DA + 0x1A * k);
        d1 += 3;
    }
}
