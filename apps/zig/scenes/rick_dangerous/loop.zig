// --------------------------------------------------------------------------
// The main loop $3D760, one pass = one frame (the model's rick_model.frame and
// rick_loop.py), resumable at its waits:
//
//   calls 0-3        the HUD
//   not dying:       Rick y <= $5F -> 7 (scroll up), y >= $CC -> 8 (down): next frame
//   dying, slot 1 empty (the death is over):
//                    lives 0 -> 19, 20, 21 (GAME OVER .. the title .. the game again);
//                    else 4, 5 (+ move.b #7,$3904A), 6: next frame
//   calls 9-14       erase, the entity pass, the bonus, the RNG, flip, wait
//                    (14 + the loop's tests; P pauses: spin until P again)
//   not dying:       x <= 0 or >= $E8 -> 15, 16, 17 (the game completed -> 20, 21)
//                    Esc -> 21; after a pause -> 18 (a VBL wait)
//
// Every call goes through io.beginCall / io.endCall: the harness's outside
// world at its entry, the VBLs it took inside it (lockstep).
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");
const game = @import("game.zig");
const io = @import("io.zig");
const clock = @import("clock.zig");
const hud = @import("hud.zig");
const fade = @import("fade.zig");
const calls = @import("calls.zig");
const wc = @import("world_calls.zig");
const exit_call = @import("exit_call.zig");
const gameover = @import("gameover.zig");
const title = @import("title.zig");
const Status = fade.Status;

pub const Exit = enum { none, gameover, complete, restart };

const Pc = enum { top, scroll, redraw, exit17, c19, c20, c21, flip, wait, pause, wait18, done };

pub const Frame = struct {
    pc: Pc = .done,
    exit: Exit = .none,
    scroll: wc.Scroll = .{},
    redraw: wc.Redraw = .{},
    sub: exit_call.SubmapExit = .{},
    fade: fade.Fade = .{},
    eog: gameover.EndOfGame = .{},
    title: title.Title = .{},

    pub fn start(self: *Frame) void {
        self.pc = .top;
        self.exit = .none;
        game.frame_vbls = 0;
    }

    pub fn step(self: *Frame) Status {
        while (true) {
            const s = switch (self.pc) {
                .top => self.top(),
                .scroll, .redraw, .exit17 => self.worldCall(),
                .c19, .c20, .c21 => self.leave(),
                .flip, .wait, .pause, .wait18 => self.waits(),
                .done => return .done,
            };
            if (s == .yield) return .yield;
        }
    }

    /// Calls 0-12, and the branches that take a long call instead.
    fn top(self: *Frame) Status {
        for (0..4) |k| calls.run(@intCast(k));
        if (m.rb(F.RICK_DYING) == 0) {
            const y = m.sw(F.R_Y);
            if (y <= 0x5F or y >= 0xCC) {
                const k: i64 = if (y <= 0x5F) 7 else 8;
                io.beginCall(k);
                clock.beginWorld(k);
                self.scroll.start(k == 7);
                self.pc = .scroll;
                return .done;
            }
        } else if (m.rw(F.R_TYPE) == 0) { // Rick's slot finished dying
            if (m.rb(F.LIVES) == 0) {
                io.beginCall(19);
                clock.beginLong(19);
                self.fade.start(true);
                self.pc = .c19;
                return .done;
            }
            calls.run(4);
            calls.run(5);
            io.beginCall(6);
            clock.beginWorld(6);
            self.redraw.start();
            self.pc = .redraw;
            return .done;
        }
        game.paused = false;
        for (9..13) |k| calls.run(@intCast(k));
        io.beginCall(13);
        self.pc = .flip;
        return .done;
    }

    /// Calls 6, 7, 8, 17: a world call running.
    fn worldCall(self: *Frame) Status {
        const st = switch (self.pc) {
            .scroll => self.scroll.step(),
            .redraw => self.redraw.step(),
            else => self.sub.step(),
        };
        if (st == .yield) return .yield;
        io.endCall();
        if (self.pc == .exit17 and m.rw(F.GAME_COMPLETE) != 0) {
            self.exit = .complete;
            self.begin20();
            return .done;
        }
        self.pc = .done;
        return .done;
    }

    /// Calls 19, 20, 21: the loop is left.
    fn leave(self: *Frame) Status {
        switch (self.pc) {
            .c19 => {
                if (self.fade.step() == .yield) return .yield;
                io.endCall();
                self.exit = .gameover;
                self.begin20();
            },
            .c20 => {
                if (self.eog.step() == .yield) return .yield;
                io.endCall();
                clock.chained();
                self.begin21();
            },
            else => {
                if (self.title.step() == .yield) return .yield;
                io.endCall();
                self.pc = .done;
            },
        }
        return .done;
    }

    fn begin20(self: *Frame) void {
        io.beginCall(20);
        clock.beginLong(20);
        self.eog.start();
        self.pc = .c20;
    }

    fn begin21(self: *Frame) void {
        io.beginCall(21);
        clock.beginLong(21);
        self.title.start();
        self.pc = .c21;
    }

    /// Call 13 (flip), call 14 (wait + the loop's tests, the P pause), call 18.
    fn waits(self: *Frame) Status {
        switch (self.pc) {
            .flip => {
                if (hud.flipBlocked()) return .yield;
                hud.flip();
                io.endCall();
                io.beginCall(14);
                self.pc = .wait;
            },
            .wait => {
                if (hud.waitBlocked()) return .yield;
                hud.wait();
                io.eventsDue(game.call_vbls); // arrived before the wait's VBL
                if (!calls.pauses()) {
                    io.endCall();
                    self.tail();
                    return .done;
                }
                m.wb(F.KEY, 0);
                self.pc = .pause;
            },
            .pause => { // the spin: until P is pressed again
                io.eventsDue(game.call_vbls + 1);
                if (m.rb(F.KEY) != 0x19 and !(io.lockstep and !io.keysLeft())) {
                    if (game.ahead()) return .yield;
                    game.vblIrq();
                    return .done;
                }
                m.wb(F.KEY, 0);
                game.paused = true;
                io.endCall();
                self.tail();
            },
            else => { // call 18: the wait after a pause
                if (hud.waitBlocked()) return .yield;
                hud.wait();
                io.endCall();
                self.pc = .done;
            },
        }
        return .done;
    }

    /// After call 14: the submap exit, Esc, the wait after a pause.
    fn tail(self: *Frame) void {
        self.pc = .done;
        if (m.rb(F.RICK_DYING) != 0) return;
        const x = m.sw(F.R_X);
        if (x <= 0 or x >= 0xE8) {
            calls.run(15);
            calls.run(16);
            io.beginCall(17);
            clock.beginWorld(17);
            self.sub.start();
            self.pc = .exit17;
            return;
        }
        if (m.rb(F.KEY) == 0x01) {
            self.exit = .restart;
            self.begin21();
            return;
        }
        if (game.paused) {
            game.paused = false;
            io.beginCall(18);
            self.pc = .wait18;
        }
    }
};
