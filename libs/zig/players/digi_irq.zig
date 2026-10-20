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
pub const big_play = @import("digi_big_play.zig");
const big_map = @import("digi_big_map.zig");
pub const mix4 = @import("digi_mix4.zig");
pub const mix3 = @import("digi_mix3.zig");
pub const tcb3 = @import("digi_tcb3.zig");
pub const mym = @import("digi_mym.zig");
pub const sfx = @import("digi_sfx.zig");
pub const tcb = @import("digi_tcb.zig");
pub const sync4 = @import("digi_sync4.zig");
pub const quartet = @import("digi_quartet.zig");

pub const Driver = union(enum) {
    big: big.Driver,
    mix4: mix4.Driver,
    mix3: mix3.Driver,
    tcb3: tcb3.Driver,
    mym: mym.Driver,
    sfx: sfx.Driver,
    tcb: tcb.Driver,
    sync4: sync4.Driver,
    quartet: quartet.Driver,
};

/// What the next interrupt must do first: check the handler in RAM (after a load or an INIT).
const Arm = enum { unarmed, armed, refused };
var state: Arm = .unarmed;
/// The B.I.G. digi PLAY (digi_big_play.zig), checked in RAM at its first call after each INIT, as the handler is.
var play_state: Arm = .unarmed;
var play_at: big_map.At = undefined;

/// Mutant 5 (sndh_native.zig, test only): every voice's step as it was when the handler was armed,
/// as if the code play patches were constant. The self-modification it misses must be caught.
pub var frozen: bool = false;
/// Mutant 6 (test only): the stream handler (digi_tcb3.zig) writes voice 2's byte to register 10
/// and voice 3's to 9.
pub var swapped: bool = false;
/// Mutant 10 (test only): maxYMiser's 8-bit drum routine (digi_mym.zig) leaves out its addi.b.
pub var no_offset: bool = false;
/// Mutant 11 (test only): the games' effect handlers (digi_sfx.zig) store the pointer past the 0 byte.
pub var sfx_end_stores: bool = false;
/// Mutant 8 (test only): the one-byte handler (digi_tcb.zig) keeps its sample pointer in Zig from
/// arming on, as if play never rewound it.
pub var pointer_kept: bool = false;
/// Mutant 7 (test only): SingSong's `(a0,d0.w)` read with the offset word unsigned (digi_quartet.zig).
pub var unsigned_index: bool = false;
var cache: [4]u32 = .{0} ** 4;

/// sndh_native.zig's mutant, as the flags above.
pub fn setMutant(n: u32) void {
    frozen = n == 5;
    big_play.short_note = n == 12;
    swapped = n == 6;
    unsigned_index = n == 7;
    pointer_kept = n == 8;
    no_offset = n == 10;
    sfx_end_stores = n == 11;
}

/// Voice `i`'s step, the immediate at `at` that play patches: read every interrupt.
pub fn step(comptime Bus: type, at: u32, i: usize) u32 {
    return if (frozen) cache[i] else digi.Access(Bus).rd32(at);
}

pub fn recognise(image: []const u8, base: u32) ?Driver {
    state = .unarmed;
    play_state = .unarmed;
    if (big.match(image, base)) |d| return .{ .big = d };
    if (mix4.match(image, base)) |d| return .{ .mix4 = d };
    if (mix3.match(image, base)) |d| return .{ .mix3 = d };
    if (tcb3.match(image, base)) |d| return .{ .tcb3 = d };
    if (mym.match(image, base)) |d| return .{ .mym = d };
    if (sfx.match(image, base)) |d| return .{ .sfx = d };
    if (tcb.match(image, base)) |d| return .{ .tcb = d };
    if (sync4.match(image, base)) |d| return .{ .sync4 = d };
    if (quartet.match(image, base)) |d| return .{ .quartet = d };
    return null;
}

pub fn status(d: Driver) digi.Status {
    return switch (d) {
        .big => |x| if (x.play != 0) .big_native else .big_digital,
        .mix4 => .hippel_mix4,
        .mix3 => .mix3_timer_c,
        .tcb3 => .tcb_streams,
        .mym => .mym_drums,
        .sfx => .game_sfx,
        .tcb => .tcb_digi,
        .sync4 => .sync_mix4,
        .quartet => .quartet_singsong,
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
    play_state = .unarmed;
}

/// Is the handler refused in RAM (it plays on Musashi until the next INIT)?
pub fn refused() bool {
    return state == .refused;
}

/// One interrupt to `handler`, natively if it is the driver's. False: Musashi's.
pub fn irq(comptime Bus: type, d: *Driver, handler: u32) bool {
    // maxYMiser's and the games' routines are many addresses (each matched where it is); the others one.
    if ((d.* != .mym and d.* != .sfx and handler != handlerAddr(d.*)) or state == .refused) return false;
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
        .mym => |*x| return mym.irq(Bus, x, handler),
        .sfx => |*x| return sfx.irq(Bus, x, handler),
        inline else => |x, tag| @field(@This(), @tagName(tag)).irq(Bus, x),
    }
    return true;
}

/// PLAY, natively if the driver has a native one (the B.I.G. digi tunes'). False: Musashi's.
/// A command past the sequencer's table ends it on Musashi too, as the 68000 would have
/// jumped into code: not seen in any of the six tunes.
pub fn play(comptime Bus: type, d: *const Driver) bool {
    if (d.* != .big or d.big.play == 0 or play_state == .refused) return false;
    if (play_state == .unarmed) {
        play_at = big_map.arm(Bus, d.big.play, d.big.addr) orelse {
            play_state = .refused;
            return false;
        };
        play_state = .armed;
    }
    big_play.play(Bus, &play_at);
    if (big_play.lost) {
        big_play.lost = false;
        play_state = .refused;
    }
    return true;
}
