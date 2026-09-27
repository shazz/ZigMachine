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
const prints = @import("intro_text.zig");
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
        while (true) {
            const s = switch (self.pc) {
                .fo, .wait1, .fi => self.upStep(),
                .loop_, .flip, .wait2 => self.loopStep(),
                .spin, .spin_wait, .fo2 => self.endStep(),
                .done => return .done,
            };
            if (s == .yield) return .yield;
        }
    }

    /// Fade out, wait, the intro screen up, fade in.
    fn upStep(self: *LoadLevel) Status {
        switch (self.pc) {
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
            else => {
                if (self.fade.step() == .yield) return .yield;
                self.pc = .loop_;
            },
        }
        return .done;
    }

    /// Until FIRE: erase, the border prints, the entity pass, flip, wait.
    fn loopStep(self: *LoadLevel) Status {
        switch (self.pc) {
            .loop_ => {
                draw.erase();
                clock.work(costs.eraseCost());
                prints.frameText();
                pass.intro();
                self.pc = .flip;
            },
            .flip => {
                if (hud.flipBlocked()) return .yield;
                screen.flipD();
                self.pc = .wait2;
            },
            else => {
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
        }
        return .done;
    }

    /// After level 4 the tune's end; fade out, clear + HUD, slot 12 off, Rick back.
    fn endStep(self: *LoadLevel) Status {
        switch (self.pc) {
            .spin => { // spins; the VBLs keep the tune going
                if (m.rw(F.MUSIC_BUSY) == 0) {
                    self.pc = .spin_wait;
                    return .done;
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
            else => {
                if (self.fade.step() == .yield) return .yield;
                screen.clearHud();
                for ([_]i64{ SLOT12, 0x3A52A, 0x3A530 }) |a| m.ww(a, 0);
                rick.flag();
                self.pc = .done;
            },
        }
        return .done;
    }

    /// Between the first fade out's wait and the fade in.
    fn screenUp(self: *LoadLevel) void {
        screen.clearHud();
        prints.pictureTiles(self.picture_tile & 0xFFFF);
        prints.textPrint(self.text);
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
