// --------------------------------------------------------------------------
// The outside world: the ACIA's stick and key bytes and the Timer A digi.
//
// LIVE. The host's key and stick events write the bytes the ACIA interrupt
// $38CE4 stores ($38CAD the stick, $38CAE the last key code, make or break)
// whenever they arrive: the game is then stopped at a VBL wait, so they land
// between two of its instructions, as on the ST. The Timer A digi advances by
// one VBL's worth of samples at every VBL (digi.zig).
//
// LOCKSTEP (the headless harness). The model's outside world, replayed from
// the fixture (tools/rick_dangerous/make_fixture.py): at each call's entry
// the ACIA / Timer A bytes the harness held, the stick and key changes during
// the call (in cycles for the long calls' clock, in VBLs for the loop's own
// tests and the pause), and the VBLs the harness took inside a call that the
// model takes at its end; at each VBL, the Timer A bytes.
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");
const game = @import("game.zig");
const digi = @import("digi.zig");
const crc = @import("crc.zig");

pub var lockstep: bool = false;

/// The fixture's tape and interrupt list (the harness fills them).
pub var tape: []const i32 = &.{};
pub var tp: usize = 0;
pub var irqs: []const i32 = &.{};
pub var ip: usize = 0;
/// The tape carries a CRC after every call (make_fixture.py --calls).
pub var per_call: bool = false;
/// Tape mismatches: the game ran another call than the harness, or ran out.
pub var errors: u32 = 0;
/// The first call whose CRC differs (per_call): the frame, the call, the tape position.
pub var bad_frame: i64 = -1;
pub var bad_call: i64 = -1;
pub var frame_no: i64 = 0;

const List = struct { at: usize = 0, n: usize = 0, i: usize = 0 };
/// The current call's events: 0 joy_events, 1 key_events (cycles), 2 joy_vbls, 3 key_vbls.
var ev: [4]List = [_]List{.{}} ** 4;
var moved: i64 = 0;
var call_k: i64 = -1;

fn next() i64 {
    if (tp >= tape.len) {
        errors += 1;
        return 0;
    }
    tp += 1;
    return tape[tp - 1];
}

/// run_call's entry: the ACIA / Timer A bytes, the call's events.
pub fn beginCall(k: i64) void {
    game.call_vbls = 0;
    call_k = k;
    if (!lockstep) {
        ev = [_]List{.{}} ** 4;
        moved = 0;
        return;
    }
    if (next() != k) errors += 1;
    var n = next();
    while (n > 0) : (n -= 1) {
        const a = next();
        m.wb(a, next());
    }
    for (&ev) |*l| {
        l.n = @intCast(@max(next(), 0));
        l.at = tp;
        l.i = 0;
        if (2 * l.n > tape.len - tp) { // a short tape: no event may read past it
            errors += 1;
            l.n = 0;
        }
        tp += 2 * l.n;
    }
    moved = next();
}

/// The call's end: the VBLs the harness took inside it (lockstep only).
pub fn endCall() void {
    if (!lockstep) return;
    while (moved > 0) : (moved -= 1) game.vblIrq();
    if (!per_call) return;
    const want = next();
    if (bad_frame < 0 and @as(u32, @bitCast(@as(i32, @truncate(want)))) != crc.state()) {
        bad_frame = frame_no;
        bad_call = call_k;
    }
}

fn evAt(l: *const List, j: usize) [2]i64 {
    return .{ tape[l.at + 2 * j], tape[l.at + 2 * j + 1] };
}

/// The stick bytes that arrived by cycle t of the call (a_clock.poll_input).
pub fn pollJoy(t: i64) void {
    const l = &ev[0];
    while (l.i < l.n and evAt(l, l.i)[0] <= t) : (l.i += 1) m.wb(F.JOY, evAt(l, l.i)[1]);
}

/// The key bytes that arrived by cycle t (d_clock.poll's second half).
pub fn pollKey(t: i64) void {
    const l = &ev[1];
    while (l.i < l.n and evAt(l, l.i)[0] <= t) : (l.i += 1) m.wb(F.KEY, evAt(l, l.i)[1]);
}

/// rick_loop._events_due: the stick / key bytes stamped before the call's VBL n.
pub fn eventsDue(n: i64) void {
    for ([2]usize{ 2, 3 }, [2]i64{ F.JOY, F.KEY }) |li, a| {
        const l = &ev[li];
        while (l.i < l.n and evAt(l, l.i)[0] < n) : (l.i += 1) m.wb(a, evAt(l, l.i)[1]);
    }
}

/// Key bytes still to come in this call (the pause spins on them).
pub fn keysLeft() bool {
    return ev[3].i < ev[3].n;
}

/// At every VBL interrupt, before the sound tick: the Timer A bytes.
pub fn irq() void {
    if (!lockstep) return digi.vbl();
    if (ip >= irqs.len) {
        errors += 1;
        return;
    }
    var n = irqs[ip];
    ip += 1;
    while (n > 0) : (n -= 1) {
        if (irqs.len - ip < 2) {
            errors += 1;
            ip = irqs.len;
            return;
        }
        m.wb(irqs[ip], irqs[ip + 1]);
        ip += 2;
    }
}

// ---------------------------------------------------------------- live input
/// The IKBD's joystick packet: $FF, then the stick byte into $38CAD.
pub fn setStick(b: u8) void {
    if (!lockstep) m.wb(F.JOY, b);
}

/// A key's make ($00-$7F) or break (| $80) code into $38CAE.
pub fn setKey(code: u8) void {
    if (!lockstep) m.wb(F.KEY, code);
}
