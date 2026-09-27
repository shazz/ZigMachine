// --------------------------------------------------------------------------
// The main loop's waits (rick_loop.py, the half after the entity pass): call
// 13 (the flip), call 14 (the VBL wait, then the loop's tests: P pauses and
// the loop spins until P again), call 18 (the wait after a pause), and the
// tests after call 14 (the submap exit, Esc). Frame.step (loop.zig) runs
// them while its pc is .flip, .wait, .pause or .wait18.
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");
const game = @import("game.zig");
const io = @import("io.zig");
const clock = @import("clock.zig");
const hud = @import("hud.zig");
const calls = @import("calls.zig");
const Frame = @import("loop.zig").Frame;
const Status = @import("fade.zig").Status;

/// Call 13 (flip), call 14 (wait + the loop's tests, the P pause), call 18.
pub fn step(f: *Frame) Status {
    switch (f.pc) {
        .flip => {
            if (hud.flipBlocked()) return .yield;
            hud.flip();
            io.endCall();
            io.beginCall(14);
            f.pc = .wait;
        },
        .wait => {
            if (hud.waitBlocked()) return .yield;
            hud.wait();
            afterWait(f);
        },
        .pause => return pauseSpin(f),
        else => { // call 18: the wait after a pause
            if (hud.waitBlocked()) return .yield;
            hud.wait();
            io.endCall();
            f.pc = .done;
        },
    }
    return .done;
}

/// Call 14 after its VBL: P pauses (the spin), else the loop's tail.
fn afterWait(f: *Frame) void {
    io.eventsDue(game.call_vbls); // arrived before the wait's VBL
    if (!calls.pauses()) {
        io.endCall();
        return tail(f);
    }
    m.wb(F.KEY, 0);
    f.pc = .pause;
}

/// The pause's spin: a VBL at a time until P is pressed again.
fn pauseSpin(f: *Frame) Status {
    io.eventsDue(game.call_vbls + 1);
    if (m.rb(F.KEY) != 0x19 and !(io.lockstep and !io.keysLeft())) {
        if (game.ahead()) return .yield;
        game.vblIrq();
        return .done;
    }
    m.wb(F.KEY, 0);
    game.paused = true;
    io.endCall();
    tail(f);
    return .done;
}

/// After call 14: the submap exit, Esc, the wait after a pause.
fn tail(f: *Frame) void {
    f.pc = .done;
    if (m.rb(F.RICK_DYING) != 0) return;
    const x = m.sw(F.R_X);
    if (x <= 0 or x >= 0xE8) {
        calls.run(15);
        calls.run(16);
        io.beginCall(17);
        clock.beginWorld(17);
        f.sub.start();
        f.pc = .exit17;
        return;
    }
    if (m.rb(F.KEY) == 0x01) {
        f.exit = .restart;
        f.begin21();
        return;
    }
    if (game.paused) {
        game.paused = false;
        io.beginCall(18);
        f.pc = .wait18;
    }
}
