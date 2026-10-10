// --------------------------------------------------------------------------
// machine-audio.wasm entry point (SEALED).
//
// The audio hardware: Paula (4 sample channels) + a YM2149 PSG + an Atari POKEY
// (audio/pokey.zig, the cycle model the FPGA's zm_pokey is held to). Reuses the chip
// implementations (audio/engine.zig, audio/ym.zig) unchanged — they ARE the
// machine primitives. Exposes a small control surface (see sdk/audio.zig) that
// the OPEN players in demo-audio.wasm drive; both modules share ONE memory on
// the AudioWorklet thread, and the players hand PCM by absolute offset into the
// shared song RAM.
// --------------------------------------------------------------------------
const std = @import("std");
const engine_mod = @import("audio/engine.zig");
const Engine = engine_mod.Engine;
const pokey_mod = @import("audio/pokey.zig");

const FRAC_BITS: u6 = 16; // Paula fixed-point (matches engine.zig)

var engine: Engine = undefined;
var pokey: pokey_mod.Pokey = .{};
var pokey_clock: pokey_mod.Clock = pokey_mod.Clock.pal;
var pokey_frac: u64 = 0;

fn clampFrames(n: u32) usize {
    return @min(@as(usize, @intCast(n)), engine_mod.MAX_FRAMES);
}

export fn machineAudioInit() void {
    engine.init();
    pokey = .{}; // power-up: SKCTL 0, init mode, until a player writes 3 as the Atari OS does
    pokey_frac = 0;
    pokey_clock = pokey_mod.Clock.pal;
}

export fn machineClear(n: u32) void {
    engine.clearBus(clampFrames(n));
}

export fn machineClamp(n: u32) void {
    engine.clampBus(clampFrames(n));
}

export fn machineMixPaula(off: u32, len: u32) void {
    const o: usize = @intCast(off);
    const e: usize = @min(o + @as(usize, @intCast(len)), engine_mod.MAX_FRAMES);
    if (e <= o) return;
    engine.mixChannels(engine.left[o..e], engine.right[o..e]);
}

export fn machineRenderYm(off: u32, len: u32) void {
    const o: usize = @intCast(off);
    const e: usize = @min(o + @as(usize, @intCast(len)), engine_mod.MAX_FRAMES);
    if (e <= o) return;
    engine.ym.render(engine.left[o..e], engine.right[o..e]);
}

/// The POKEY's four channels into [off, off+len), added on both sides, unipolar
/// like the YM: all four at volume 15 is full scale.
export fn machineRenderPokey(off: u32, len: u32) void {
    const o: usize = @intCast(off);
    const e: usize = @min(o + @as(usize, @intCast(len)), engine_mod.MAX_FRAMES);
    if (e <= o) return;
    pokey.renderAdd(engine.left[o..e], engine.right[o..e], 44100, pokey_clock, &pokey_frac);
}

/// A POKEY register ($D200 + reg: AUDF/AUDC 0-7, AUDCTL 8, STIMER 9, SKCTL 15).
export fn machinePokeyWrite(reg: u32, val: u32) void {
    pokey.write(@truncate(reg), @truncate(val));
}

/// The POKEY's machine clock: 1 PAL (1773447 Hz, a SAP without the NTSC tag), 0 NTSC.
export fn machinePokeyClock(pal: u32) void {
    pokey_clock = if (pal != 0) pokey_mod.Clock.pal else pokey_mod.Clock.ntsc;
    pokey_frac = 0; // the cycle count restarts here, as the FPGA's zm_audio_pokey does: sample for sample
}

export fn machineYmWrite(reg: u32, val: u32) void {
    engine.ym.writeReg(@intCast(reg), @intCast(val));
}

export fn machinePaulaClearScopes() void {
    engine.clearScopes();
}

/// Silence the sound chip — the machine reclaiming it when a program ends.
///
/// A cart cannot switch its own music off on the way out: the host replaces it
/// and its stop() never runs, so the outgoing screen's tune plays on over the
/// next one. The video half already has this (hwInit -> video.reset()); this is
/// the audio half, and the host calls it on every cart instantiation.
///
/// Deliberately NOT `engine.init()`: that would zero the output bus and the
/// scope buffers mid-render. This only quiets the chip — mixer off, the three
/// channel volumes to zero, every Paula channel stopped — so it is safe to call
/// between two renders on the worklet thread.
export fn machineAudioReset() void {
    engine.ym.writeReg(7, 0x3F); // mixer: tone AND noise off on A, B and C
    engine.ym.writeReg(8, 0); // channel A volume (also clears envelope mode)
    engine.ym.writeReg(9, 0); // channel B
    engine.ym.writeReg(10, 0); // channel C
    for (&engine.channels) |*c| c.active = false;
    for (0..4) |ch| pokey.write(@intCast(2 * ch + 1), 0); // the POKEY's four volumes to zero
    engine.clearScopes();
}

// (Re)start a channel from song RAM: mirrors the pre-seal player's trigger()
// (sets data/pos/loop/pan/active; step & volume are set separately per row).
export fn machinePaulaTrigger(ch: u32, data_abs: u32, data_len: u32, loop_start: u32, loop_len: u32, pan: f32) void {
    if (ch >= engine_mod.NUM_CHANNELS) return;
    var c = &engine.channels[@intCast(ch)];
    const ptr: [*]const i8 = @ptrFromInt(@as(usize, @intCast(data_abs)));
    c.data = ptr[0..@intCast(data_len)];
    c.pos = 0;
    c.loop_start = loop_start;
    c.loop_len = loop_len;
    c.pan = pan;
    c.active = true;
}

export fn machinePaulaSetStep(ch: u32, step: u32) void {
    if (ch >= engine_mod.NUM_CHANNELS) return;
    engine.channels[@intCast(ch)].step = step;
}

export fn machinePaulaSetVolume(ch: u32, vol: f32) void {
    if (ch >= engine_mod.NUM_CHANNELS) return;
    engine.channels[@intCast(ch)].volume = vol;
}

export fn machinePaulaSetPan(ch: u32, pan: f32) void {
    if (ch >= engine_mod.NUM_CHANNELS) return;
    engine.channels[@intCast(ch)].pan = pan;
}

export fn machinePaulaSetPos(ch: u32, pos_samples: u32) void {
    if (ch >= engine_mod.NUM_CHANNELS) return;
    engine.channels[@intCast(ch)].pos = @as(u64, @intCast(pos_samples)) << FRAC_BITS;
}

export fn machinePaulaSetActive(ch: u32, on: u32) void {
    if (ch >= engine_mod.NUM_CHANNELS) return;
    engine.channels[@intCast(ch)].active = (on != 0);
}

// --- pointers the worklet reads (into the shared memory) ---
export fn audioLeftPtr() [*]f32 {
    return @ptrCast(&engine.left);
}
export fn audioRightPtr() [*]f32 {
    return @ptrCast(&engine.right);
}
export fn audioMaxFrames() u32 {
    return @intCast(engine_mod.MAX_FRAMES);
}
export fn audioScopePtr(ch: u32) [*]f32 {
    return @ptrCast(&engine.channels[@intCast(ch)].scope);
}
export fn audioScopeLen() u32 {
    return @intCast(engine_mod.SCOPE_LEN);
}
export fn audioYmRegsPtr() [*]u8 {
    return @ptrCast(&engine.ym.regs);
}
export fn audioVersion() u32 {
    return 0x0001_0000;
}
