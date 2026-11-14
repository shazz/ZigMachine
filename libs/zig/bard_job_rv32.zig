// --------------------------------------------------------------------------
// The BARD job server's C entry for BARD's firmware (fpga/cycles/sound/sjobs.c):
// bard_jobs/server.zig built for rv32i + Zmmul (fpga/cycles/sound.mk, `zig
// build-obj -mcpu=generic_rv32+zmmul`), the same source the cart's wasm runs.
// The cart's memory is DDR at `base` (ZIGGY's view and BARD's are the same
// addresses); the clock is BARD's own cycle counter (sjobs.c bjob_now).
// --------------------------------------------------------------------------
const S = @import("bard_jobs/server.zig");
const zx0 = @import("depackers/zx0.zig");

extern fn bjob_now() u32;

const Clock = struct {
    pub fn now() u32 {
        return bjob_now();
    }
};

var srv: S.Server(Clock, zx0) = .{};

/// Serve the cart's block (its offset) in its memory [base, base + size), from post `head` on. 0: refused.
export fn bjob_open(base: u32, size: u32, block: u32, head: u32) u32 {
    return @intFromBool(srv.open(.{ .base = base, .size = size }, block, head));
}

/// Drop the block and any job in progress (the cart went away).
export fn bjob_close() void {
    srv = .{};
}

/// Serve up to post `head` for about `budget` cycles: 0 idle, 1 a job half done, 2 a slot not whole yet.
export fn bjob_step(head: u32, budget: u32) u32 {
    return @intFromEnum(srv.step(head, budget));
}
