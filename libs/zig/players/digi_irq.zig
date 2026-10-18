// --------------------------------------------------------------------------
// Handler-only native drivers: the tune's timer interrupt in Zig, its init,
// play and exit left on Musashi.
//
// Why only the handler: on BARD a call into Musashi costs ~17.8 k cycles
// whatever it runs (docs/FPGA_SOUND_CPU.md "Every cart's music"), and a digi
// tune makes one a sample: 120 to 270 a 60 Hz frame. Its 50 Hz play is one
// call a frame. So the handler is where the cost is, and it is also the small,
// fixed part of a replay: a sequencer is the composer's, a handler is the
// converter's, shared by every tune he converted. Musashi and the native
// handler keep the tune's state in the same RAM, so they hand over at any call.
//
// The handler is recognised in the image at load (a masked hash: the steps and
// addresses that move are holes). Many of these tunes copy and relocate their
// code in init, so the handler is checked again in RAM, and its addresses read
// there, at its first interrupt after each INIT (`arm`). If it no longer
// matches, it plays on Musashi until the next INIT.
// --------------------------------------------------------------------------
const digi = @import("digi.zig");
pub const big = @import("digi_big.zig");
pub const mix4 = @import("digi_mix4.zig");
pub const mix3 = @import("digi_mix3.zig");
pub const tcb3 = @import("digi_tcb3.zig");

pub const Driver = union(enum) {
    big: big.Driver,
    mix4: mix4.Driver,
    mix3: mix3.Driver,
    tcb3: tcb3.Driver,
};

/// What the next interrupt must do first: check the handler in RAM (after a load or an INIT).
var state: enum { unarmed, armed, refused } = .unarmed;

/// Mutant 5 (sndh_native.zig, test only): every voice's step as it was when the handler was armed,
/// as if the code play patches were constant. The self-modification it misses must be caught.
pub var frozen: bool = false;
/// Mutant 6 (test only): the stream handler (digi_tcb3.zig) writes voice 2's byte to register 10
/// and voice 3's to 9.
pub var swapped: bool = false;
var cache: [4]u32 = .{0} ** 4;

/// Voice `i`'s step, the immediate at `at` that play patches: read every interrupt.
pub fn step(comptime Bus: type, at: u32, i: usize) u32 {
    return if (frozen) cache[i] else digi.Access(Bus).rd32(at);
}

pub fn recognise(image: []const u8, base: u32) ?Driver {
    state = .unarmed;
    if (big.match(image, base)) |d| return .{ .big = d };
    if (mix4.match(image, base)) |d| return .{ .mix4 = d };
    if (mix3.match(image, base)) |d| return .{ .mix3 = d };
    if (tcb3.match(image, base)) |d| return .{ .tcb3 = d };
    return null;
}

pub fn status(d: Driver) digi.Status {
    return switch (d) {
        .big => .big_digital,
        .mix4 => .hippel_mix4,
        .mix3 => .mix3_timer_c,
        .tcb3 => .tcb_streams,
    };
}

pub fn handlerAddr(d: Driver) u32 {
    return switch (d) {
        inline else => |x| x.addr,
    };
}

/// INIT is about to run on Musashi: it may move or rewrite the handler.
pub fn reinit() void {
    state = .unarmed;
}

/// Is the handler refused in RAM (it plays on Musashi until the next INIT)?
pub fn refused() bool {
    return state == .refused;
}

/// One interrupt to `handler`, natively if it is the driver's. False: Musashi's.
pub fn irq(comptime Bus: type, d: *Driver, handler: u32) bool {
    if (handler != handlerAddr(d.*) or state == .refused) return false;
    if (state == .unarmed) {
        const ok = switch (d.*) {
            inline else => |*x, tag| blk: {
                const Mod = @field(@This(), @tagName(tag));
                for (Mod.STEP, 0..) |s, i| cache[i] = digi.Access(Bus).rd32(x.addr + s);
                break :blk Mod.arm(Bus, x);
            },
        };
        state = if (ok) .armed else .refused;
        if (!ok) return false;
    }
    switch (d.*) {
        inline else => |x, tag| @field(@This(), @tagName(tag)).irq(Bus, x),
    }
    return true;
}
