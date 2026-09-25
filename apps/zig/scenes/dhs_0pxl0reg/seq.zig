// --------------------------------------------------------------------------
// The VBL ($1020C) and the main loop, one 50 Hz frame per tick():
//   VBL: step the sequencer ($102A6, 28-byte entries), call the entry's vbl
//        hook, the music, the post-music hook; program Timer A
//   main loop: the entry's main hook, whenever the previous call has returned
//   Timer A: the kernel, which writes colour 0 down the screen
// When a main-loop call starts and whether it lands before or after that
// frame's Timer A are replayed from the emulator's measurement (rip.CALL_RUNS),
// since they decide what several parts show: P12's fire updates only about
// every other frame, P7's render is torn at row 22, and the renders that
// overrun Timer A show a frame late. Work a hook does after the kernel
// preempted it runs from core.after, once the kernel is done.
// --------------------------------------------------------------------------
const core = @import("core.zig");
const out = @import("out.zig");
const rip = @import("rip.zig");
const hooks = @import("hooks.zig");
const music = @import("music.zig");

const Hook = rip.Hook;
const NHOOKS = @typeInfo(Hook).@"enum".fields.len;

pub var frame: u32 = 0; // the VBL count, 1 at the first VBL (model frame F)
var entry: usize = 0;
var left: u32 = 0;
var spent: [NHOOKS]bool = undefined;
var run: usize = 0; // cursor into CALL_RUNS
var run_left: u32 = 0;

pub fn reset() void {
    core.reset();
    out.reset();
    hooks.reset();
    frame = 0;
    entry = 0;
    left = rip.SEQ[0].frames;
    @memset(&spent, false);
    run = 0;
    run_left = if (rip.CALL_RUNS.len > 0) rip.CALL_RUNS[0] & 0x3FFF else 0;
}

/// A hook that plants an rts over itself runs once.
fn call(h: Hook) void {
    if (h == .nop) return;
    const i = @intFromEnum(h);
    if (spent[i]) return;
    if (isOnce(h)) spent[i] = true;
    hooks.call(h, frame);
}

fn isOnce(h: Hook) bool {
    for (rip.ONCE) |o| if (o == h) return true;
    return false;
}

/// This frame's main-loop call: 0 none, 1 before the kernel, 2 after it.
fn callCode() u16 {
    if (frame > rip.CALLS_LAST_FRAME) return 0;
    while (run_left == 0) {
        run += 1;
        run_left = rip.CALL_RUNS[run] & 0x3FFF;
    }
    run_left -= 1;
    return rip.CALL_RUNS[run] >> 14;
}

pub fn tick() void {
    frame += 1;
    left -%= 1; // the last entry's $FFFFFFFF frames: P17 forever
    if (left == 0) {
        entry += 1;
        left = rip.SEQ[entry].frames;
    }
    const e = rip.SEQ[entry];
    call(e.vbl);
    call(e.post);
    const code = callCode();
    if (code == 1) call(e.main);
    out.begin(core.colour);
    if (e.l0 != 0 and e.kernel != .nop) hooks.kernel(e.kernel, e.l0);
    for (core.after[0..core.after_n]) |job| hooks.finish(job);
    core.after_n = 0;
    if (code == 2) call(e.main);
    music.tick(frame);
}
