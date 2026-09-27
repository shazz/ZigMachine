// --------------------------------------------------------------------------
// The level load $3B00A and its intro screen $3B076 (the model's d_intro.py
// and a_level.load_level), resumable: fade out, wait, clear + HUD, the 6x6
// picture frame, the text, the screen -> $65B00, every slot cleared, slot
// 12 = the animated picture (type 74), the level's tune (id = level), fade
// in; then until FIRE: erase, the border prints, the entity pass, flip,
// wait. After level 4 (the congratulations) it waits for the tune to end.
// Fade out, clear + HUD, slot 12 off, Rick back in slot 1.
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");
const core = @import("core.zig");
const clock = @import("clock.zig");
const costs = @import("costs.zig");
const game = @import("game.zig");
const hud = @import("hud.zig");
const screen = @import("screen.zig");
const snd = @import("sound.zig");
const draw = @import("draw.zig");
const pass = @import("pass.zig");
const rick = @import("rick.zig");
const fade = @import("fade.zig");
const Status = fade.Status;

const SLOT12: i64 = 0x3A514;

pub const LoadLevel = struct {
    pc: enum { fo, wait1, fi, loop_, flip, wait2, spin, spin_wait, fo2, done } = .fo,
    fade: fade.Fade = .{},
    a1: i64 = 0,
    picture_tile: i64 = 0,
    text: i64 = 0,

    /// $3B00A: Rick x/y, map_row, submap from the level record; 6 bullets and
    /// 6 dynamite (HUD dirty); then the intro screen $3B076.
    pub fn start(self: *LoadLevel) void {
        self.* = .{};
        const a0 = F.LEVELS + ((m.rw(F.LEVEL) * 0x14) & 0xFFFFFFFF);
        m.ww(F.R_X, m.rw(a0 + 4));
        m.ww(F.R_Y, m.rw(a0 + 6));
        m.ww(F.MAP_ROW, m.rw(a0 + 8));
        m.wl(F.SUBMAP, m.rl(a0 + 0xA));
        m.wb(F.BULLETS, 6);
        m.wb(F.DYNAMITE, 6);
        m.wb(F.DIRTY_BULLETS, 0xFF);
        m.wb(F.DIRTY_DYNAMITE, 0xFF);
        self.picture_tile = m.rw(a0 + 0xE);
        self.text = m.rl(a0);
        self.a1 = m.rl(a0 + 0x10);
        self.fade.start(true);
    }

    pub fn step(self: *LoadLevel) Status {
        while (true) switch (self.pc) {
            .fo => {
                if (self.fade.step() == .yield) return .yield;
                self.pc = .wait1;
            },
            .wait1 => {
                if (hud.waitBlocked()) return .yield;
                screen.waitD();
                self.screenUp();
                self.fade.start(false);
                self.pc = .fi;
            },
            .fi => {
                if (self.fade.step() == .yield) return .yield;
                self.pc = .loop_;
            },
            .loop_ => {
                draw.erase();
                clock.work(costs.eraseCost());
                frameText();
                pass.intro();
                self.pc = .flip;
            },
            .flip => {
                if (hud.flipBlocked()) return .yield;
                screen.flipD();
                self.pc = .wait2;
            },
            .wait2 => {
                if (hud.waitBlocked()) return .yield;
                screen.waitD();
                if (m.rb(F.JOY) & 0x80 == 0) {
                    self.pc = .loop_;
                } else if (m.rw(F.LEVEL) == 4) {
                    self.pc = .spin;
                } else {
                    self.fade.start(true);
                    self.pc = .fo2;
                }
            },
            .spin => { // spins; the VBLs keep the tune going
                if (m.rw(F.MUSIC_BUSY) == 0) {
                    self.pc = .spin_wait;
                    continue;
                }
                if (game.ahead()) return .yield;
                clock.work(clock.VBL - clock.pos);
            },
            .spin_wait => {
                if (hud.waitBlocked()) return .yield;
                screen.waitD();
                self.fade.start(true);
                self.pc = .fo2;
            },
            .fo2 => {
                if (self.fade.step() == .yield) return .yield;
                screen.clearHud();
                for ([_]i64{ SLOT12, 0x3A52A, 0x3A530 }) |a| m.ww(a, 0);
                rick.flag();
                self.pc = .done;
            },
            .done => return .done,
        };
    }

    /// Between the first fade out's wait and the fade in.
    fn screenUp(self: *LoadLevel) void {
        screen.clearHud();
        pictureTiles(self.picture_tile & 0xFFFF);
        textPrint(self.text);
        m.copy(0x65B00, 0x78000, 0x8000);
        clock.work(8 * 20 * 1024 + 10 * 1024);
        hud.clearSlots();
        m.ww(SLOT12, 0x4A);
        m.ww(SLOT12 + 4, m.rw(self.a1));
        m.ww(SLOT12 + 6, m.rw(self.a1 + 2));
        m.wl(0x3A54A, self.a1 + 4);
        m.wl(0x3A546, m.rl(self.a1 + 4 + 6));
        for ([_]i64{ 0x3A53E, 0x3A540, 0x3A542 }) |a| m.ww(a, 0);
        clock.work(1500);
        snd.play(m.rw(F.LEVEL), 0);
    }
};

/// 6 rows of the 6 tiles d2, d2+1, ... ($38EE8 at $1941 + n x $500).
fn pictureTiles(d2_: i64) void {
    var d2 = d2_;
    var d0: i64 = 0x1941;
    for (0..6) |_| {
        var k: i64 = 0;
        while (k < 6) : (k += 1) {
            m.wb(0x3B23C + k, d2);
            d2 = (d2 + 1) & 0xFFFF;
        }
        clock.work(180 + clock.PRINT_CHAR * 6 + 150);
        core.printText(d0, 0x3B23C);
        d0 = (d0 + 0x500) & 0xFFFF;
    }
}

/// One tile per column from column 5; $FF = the next line (row 2, then 13,
/// 14, ..); $FE = the end.
fn textPrint(a2_: i64) void {
    var a2 = a2_;
    var d1: i64 = 2;
    while (true) {
        var d0: i64 = 5;
        while (true) {
            const d2 = m.rb(a2);
            a2 += 1;
            if (d2 == 0xFF) {
                d1 += 1;
                if (d1 == 3) d1 = 0xD;
                break;
            }
            if (d2 == 0xFE) return;
            m.wb(0x3B23A, d2);
            screen.printAt(d0, d1, 0x3B23A);
            d0 += 1;
        }
    }
}

/// $3B18A..$3B1E6: the border prints on single screens.
fn frameText() void {
    _ = screen.printOne(0x79440, 0x3B244);
    for ([2][2]i64{ .{ 0x79940, 0x3B258 }, .{ 0x71440, 0x3B25A } }) |bt| {
        var a1 = bt[0];
        for (0..7) |_| {
            _ = screen.printOne(a1, bt[1]);
            a1 += 0x19;
            _ = screen.printOne(a1, bt[1]);
            a1 += 0x4E7;
        }
        if (bt[0] == 0x71440) _ = screen.printOne(a1, 0x3B24E);
    }
}
