// --------------------------------------------------------------------------
// The headless harness's door to the cracktro and the trainer
// (apps/rick_cracktro_headless.mjs), exported by rick_dangerous.zig.
//
//   trainer(mask)    the trainer flags (trainer.zig: 1 lives, 2 bullets,
//                    4 dynamite), for the lockstep replays
//   restart(orig)    the cracktro from its start again; orig = 1 types the
//                    ORIGINAL text (CABAL), to compare with Hatari's screens
//   val(what)        0 phase (0 typing, 1 trainer, 2 done), 1 the text
//                    position (a5), 2 VBLs left in the wait, 3 the question,
//                    4 the trainer mask, 5 the cracktro's VBLs, 6 the cursor
//                    shown, 7 cursor moves left, 8 a page clear pending
// --------------------------------------------------------------------------
const Front = @import("front.zig").Front;
const text = @import("cracktro_text.zig");
const trainer_flags = @import("trainer.zig");

pub var front: ?*Front = null;

pub fn trainer(mask: u32) callconv(.c) void {
    trainer_flags.set(mask);
}

pub fn restart(orig: u32) callconv(.c) void {
    const f = front orelse return;
    const vt = f.crack.vt;
    f.start(vt.fb, vt.font, if (orig != 0) text.ORIGINAL else text.RICK);
}

pub fn val(what: u32) callconv(.c) i32 {
    const f = front orelse return -1;
    const c = &f.crack;
    return switch (what) {
        0 => @intFromEnum(c.phase),
        1 => c.pos,
        2 => c.wait,
        3 => c.question,
        4 => @intCast(trainer_flags.mask()),
        5 => @intCast(f.vbls),
        6 => @intFromBool(c.vt.shown),
        7 => c.moves,
        8 => @intFromBool(c.page),
        else => -1,
    };
}
