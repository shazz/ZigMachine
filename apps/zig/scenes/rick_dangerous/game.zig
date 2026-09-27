// --------------------------------------------------------------------------
// What the game's state holds outside its RAM (the model's GameState fields):
// the Shifter's colour registers and video base, the VBL counts, and the VBL
// interrupt $38D7C itself.
//
// PACING. The loop is VBL-locked (a frame = the flip's VBL + the wait's VBL,
// 25 Hz), and the long calls count the ST's cycles (clock.zig). The ST's VBL
// clock is `vbls`; the host lets the game run up to `limit` (its own time in
// 50 Hz VBLs). The game stops only where the original WAITS for a VBL: there,
// ahead() says the next VBL would pass the host's time, and the resumable
// routine (tasks.zig) yields, to continue at the same wait on a later host
// frame. The headless harness runs in lockstep and never yields.
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");
const io = @import("io.zig");
const player = @import("player.zig");

/// The 16 colour registers (fades write them; not in RAM).
pub var pal: [16]i64 = [_]i64{0} ** 16;
/// The displayed screen's base ($38DB8 writes it).
pub var vbase: i64 = 0xF8000;
/// VBLs taken in the current frame / the current call / since power-on.
pub var frame_vbls: u32 = 0;
pub var call_vbls: u32 = 0;
pub var vbls: u64 = 0;
/// The host's time, in VBLs: the game runs no further (see ahead()).
pub var limit: u64 = 0;
/// The P pause ended in this frame (the loop then runs call 18).
pub var paused: bool = false;

/// The next VBL wait would run past the host's time: yield before it.
pub fn ahead() bool {
    return !io.lockstep and vbls + 1 > limit;
}

/// $38D7C, the VBL interrupt: addi.b #1,$38DB6; bsr $3488E (the sound tick).
/// The Timer A digi bytes (the audio clock) are updated first: io.irq().
pub fn vblIrq() void {
    frame_vbls += 1;
    call_vbls += 1;
    vbls += 1;
    io.irq();
    m.wb(F.VBL_COUNT, m.rb(F.VBL_COUNT) + 1);
    player.tick();
}

pub fn backScreen() i64 {
    return m.rl(F.SCREEN_PTR) ^ 0x8000;
}
