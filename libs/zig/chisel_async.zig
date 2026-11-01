// --------------------------------------------------------------------------
// CHISEL's lazy wait (KESTREL). On the board hwBlit() spins until CHISEL is
// done, ~500 cycles for even a tiny op and ~1 cycle a byte on top: time the
// cart CPU could spend on work that does not touch the op's pixels. With
// BLIT_ASYNC set, hwBlit() returns as soon as CHISEL has started, and the wait
// moves to the next point that needs it: the next hwBlit, a sync(), any call
// into the machine or the ROM, the end of the frame (fpga/cycles/bchisel.h).
//
// The cart's side of the bargain: between an async hwBlit and the next sync it
// must not read or write the op's destination pixels (nor overwrite its
// source). Every blitter op of the period runs lazily, ZigOS's own clears and
// copies included (LogicalFB.clearFrameBuffer, blit.Dst.fill): a CPU drawing
// into a plane CHISEL is still clearing would be erased by the clear.
//
// The machine's blitter is synchronous and never reads BLIT_ASYNC, so in the
// browser (and every scene_hash) nothing changes: a sync there is a NOP blit.
// Invariant kept here: async OFF => nothing pending, so sync() is one load
// when the cart never asked for async.
// --------------------------------------------------------------------------
const hw = @import("hardware");

/// Let hwBlit() return before CHISEL finishes (on), or go back to waiting (off,
/// which syncs first so nothing is left running behind the cart's back).
pub fn setAsync(base: usize, on: bool) void {
    if (base == 0) return; // ZigOS not initialised: no machine to ask
    const p: *volatile u8 = @ptrFromInt(base + hw.BLIT_ASYNC);
    if ((p.* != 0) == on) return;
    if (!on) sync(base);
    p.* = @intFromBool(on);
}

pub fn isAsync(base: usize) bool {
    if (base == 0) return false;
    const p: *const volatile u8 = @ptrFromInt(base + hw.BLIT_ASYNC);
    return p.* != 0;
}

/// Wait for the lazy op, if any: after this the CPU may touch its pixels and
/// CYCLES is that op's. A NOP hwBlit, COMMAND put back as the cart left it.
pub fn sync(base: usize) void {
    if (!isAsync(base)) return;
    const cmd: *volatile u8 = @ptrFromInt(base + hw.BLIT_COMMAND);
    const was = cmd.*;
    if (was != hw.BLIT_CMD_NOP) cmd.* = hw.BLIT_CMD_NOP;
    hw.hwBlit();
    if (was != hw.BLIT_CMD_NOP) cmd.* = was;
}
