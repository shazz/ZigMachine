// --------------------------------------------------------------------------
// The headless harness's door (apps/joust_headless.mjs): run the machine in
// lockstep, one game frame at a time, with the recorded inputs, and read back
// what the reference says it must hold. Exported by joust.zig's comptime
// block, in JOUST's cart only.
// --------------------------------------------------------------------------
const std = @import("std");
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const machine = @import("machine.zig");

/// The machine the scene runs (set by its init).
pub var m: ?*machine.Machine = null;
/// The harness drives the machine; the scene's update stands aside.
pub var lockstep: bool = false;

const REGIONS = [_][2]usize{ .{ 0x0D00, 0x1C90 }, .{ 0x81CC, 0x8210 }, .{ 0x86DA, 0x8710 } };
const pal_none = [_]u16{0} ** 16;

pub fn reset(seed: u32) callconv(.c) void {
    const mm = m orelse return;
    lockstep = true;
    mm.reset(seed);
    cyc.errors = 0;
}

/// A key whose ACIA service starts at cycle (hi << 32 | lo).
pub fn key(hi: u32, lo: u32, code: u32) callconv(.c) void {
    const mm = m orelse return;
    mm.st.pacer.addKey((@as(i64, hi) << 32) | lo, code);
}

/// Run to the next frame boundary ($0018) with these joystick bytes; returns
/// the VBLs the frame took.
pub fn frame(p1: u32, p2: u32) callconv(.c) i32 {
    const mm = m orelse return -1;
    mm.joy = .{ @truncate(p1), @truncate(p2) };
    mm.run(1 << 62, true);
    return std.math.cast(i32, mm.frame_vbls) orelse -1;
}

/// --break: charge extra cycles, as a one-instruction transcription slip would.
pub fn nudge(cycles: u32) callconv(.c) void {
    const mm = m orelse return;
    mm.st.pacer.run(&mm.st, cycles);
}

/// FNV-1a of the game's RAM ($0D00-$1C90, $81CC-$8210, $86DA-$8710) + the screen.
pub fn hash() callconv(.c) u32 {
    var h: u32 = 0x811C9DC5;
    for (REGIONS) |r| {
        for (State.mem[r[0]..r[1]]) |b| h = (h ^ b) *% 0x01000193;
    }
    for (State.scr[State.BELOW..]) |b| h = (h ^ b) *% 0x01000193;
    return h;
}

/// 0/1 the CPU clock (lo/hi), 2 VBLs, 3 frames, 4 mode, 5 out-of-range
/// accesses, 6 cycle-table errors, 7 SFX started, 8.. their numbers.
pub fn val(what: u32) callconv(.c) u32 {
    const mm = m orelse return 0;
    const st = &mm.st;
    const t: u64 = @bitCast(st.pacer.t);
    return switch (what) {
        0 => @truncate(t),
        1 => @truncate(t >> 32),
        2 => @truncate(@as(u64, @bitCast(st.pacer.vbl))),
        3 => @truncate(mm.frames),
        4 => @intFromEnum(mm.mode),
        5 => st.oob,
        6 => cyc.errors,
        7 => st.sfx_n,
        else => if (what - 8 < st.sfx_n) st.sfx_log[what - 8] else 0,
    };
}

/// The ST screen (32000 bytes, planar) and the 16 colour registers, for the
/// harness to decode itself.
pub fn screenPtr() callconv(.c) [*]const u8 {
    return State.scr[State.BELOW..].ptr;
}
pub fn palPtr() callconv(.c) [*]const u16 {
    const mm = m orelse return &pal_none;
    return &mm.st.pal;
}

/// Forget the SFX log (the harness reads it after every frame).
pub fn sfxClear() callconv(.c) void {
    const mm = m orelse return;
    mm.st.sfx_n = 0;
}
