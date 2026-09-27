// --------------------------------------------------------------------------
// The headless harness's door (apps/rick_dangerous_headless.mjs), exported by
// rick_dangerous.zig's comptime block in this cart only.
//
//   buf(n)          a test buffer from the cart RAM arena (once; the harness
//                   asks for the largest run's size)
//   load(...)       a fixture run: the first key frame's snapshot, the palette
//                   and video base, the tape and the interrupt list
//   frame()         one frame of the loop in lockstep; returns its VBLs
//   val(what)       0 the state CRC, 1 tape errors, 2 out-of-range accesses,
//                   3/4 the first call whose CRC differs (frame, call), 5 the
//                   frame's sound requests, 6 unknown handler types, 7 frames,
//                   8/9 the tape / interrupt positions, 10 VBLs, 100+i request i
//   poke / irq / refuse   the --break modes' faults
//   sndBegin / sndTick    the sound driver alone, for the SNDH comparison
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const m = @import("ram.zig");
const game = @import("game.zig");
const io = @import("io.zig");
const crc = @import("crc.zig");
const snd = @import("sound.zig");
const player = @import("player.zig");
const digi = @import("digi.zig");
const handlers = @import("handlers.zig");
const machine = @import("machine.zig");

var tbuf: []u8 = &.{};

pub fn buf(n: u32) callconv(.c) ?[*]u8 {
    if (tbuf.len < n) tbuf = zg.mem.alloc(u8, n) orelse return null;
    return tbuf.ptr;
}

pub fn load(snap_len: u32, ints_off: u32, tape_n: u32, irq_n: u32, per_call: u32) callconv(.c) i32 {
    if (m.mem.len == 0 or snap_len != crc.regionBytes()) return -1;
    if (ints_off % 4 != 0 or ints_off + 4 * (17 + tape_n + irq_n) > tbuf.len) return -2;
    m.loadImage();
    crc.load(tbuf[0..snap_len]);
    const ints: [*]const i32 = @ptrCast(@alignCast(tbuf.ptr + ints_off));
    var pal: [16]i64 = undefined;
    for (&pal, 0..) |*p, i| p.* = ints[i];
    machine.loadLockstep(pal, ints[16]);
    io.tape = ints[17 .. 17 + tape_n];
    io.irqs = ints[17 + tape_n .. 17 + tape_n + irq_n];
    io.tp = 0;
    io.ip = 0;
    io.errors = 0;
    io.per_call = per_call != 0;
    io.bad_frame = -1;
    io.bad_call = -1;
    io.frame_no = 0;
    return 0;
}

pub fn frame() callconv(.c) i32 {
    const v = machine.runFrame();
    snd.flush();
    io.frame_no += 1;
    return std.math.cast(i32, v) orelse -1;
}

pub fn val(what: u32) callconv(.c) u32 {
    return switch (what) {
        0 => crc.state(),
        1 => io.errors,
        2 => m.oob,
        3 => @bitCast(@as(i32, @truncate(io.bad_frame))),
        4 => @bitCast(@as(i32, @truncate(io.bad_call))),
        5 => @intCast(snd.log_n),
        6 => handlers.unknown,
        7 => @truncate(machine.frames),
        8 => @intCast(io.tp),
        9 => @intCast(io.ip),
        10 => @truncate(game.vbls),
        else => if (what >= 100 and what - 100 < snd.log_n) snd.log[what - 100] else 0,
    };
}

/// --break: a byte of the game's RAM changed, as one wrong store would.
pub fn poke(addr: u32, v: u32) callconv(.c) void {
    m.wb(addr, v);
}

/// --break: one VBL interrupt too many.
pub fn irq() callconv(.c) void {
    io.lockstep = false;
    game.vblIrq();
    io.lockstep = true;
}

/// --break: a zg.mem allocation the arena refuses (the harness must notice).
pub fn refuse() callconv(.c) void {
    _ = zg.mem.alloc(u8, 64 << 20);
}

/// The sound driver alone, from the entry image: sound off, sfx_alt, then
/// play_sound(id, d1) exactly as rick_dangerous.sndh's init does for subtune
/// 1 + id + 29 x v.
pub fn sndBegin(subtune: u32) callconv(.c) void {
    m.loadImage();
    io.lockstep = false;
    digi.reset();
    snd.off();
    const n: i64 = subtune - 1;
    const v = @divFloor(n, snd.NIDS);
    if (v != 2) m.wb(0x34A85, v);
    snd.play(@mod(n, snd.NIDS), if (v == 2) 1 else 0);
}

/// One VBL of the driver: the Timer A samples, then the tick $3488E.
pub fn sndTick() callconv(.c) void {
    digi.vbl();
    player.tick();
}

pub fn memPtr() callconv(.c) ?[*]const u8 {
    if (m.mem.len == 0) return null;
    return m.mem.ptr;
}

pub fn palPtr() callconv(.c) [*]const i64 {
    return &game.pal;
}

pub fn vbase() callconv(.c) u32 {
    return @truncate(@as(u64, @bitCast(game.vbase)));
}
