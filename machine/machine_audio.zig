// --------------------------------------------------------------------------
// machine-audio.wasm entry point (SEALED).
//
// The audio hardware: Paula (4 sample channels) + a YM2149 PSG. Reuses the chip
// implementations (audio/engine.zig, audio/ym.zig) unchanged — they ARE the
// machine primitives. Exposes a small control surface (see sdk/audio.zig) that
// the OPEN players in demo-audio.wasm drive; both modules share ONE memory on
// the AudioWorklet thread, and the players hand PCM by absolute offset into the
// shared song RAM.
// --------------------------------------------------------------------------
const std = @import("std");
const engine_mod = @import("audio/engine.zig");
const Engine = engine_mod.Engine;

const FRAC_BITS: u6 = 16; // Paula fixed-point (matches engine.zig)

var engine: Engine = undefined;

fn clampFrames(n: u32) usize {
    return @min(@as(usize, @intCast(n)), engine_mod.MAX_FRAMES);
}

export fn machineAudioInit() void {
    engine.init();
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

export fn machineYmWrite(reg: u32, val: u32) void {
    engine.ym.writeReg(@intCast(reg), @intCast(val));
}

export fn machinePaulaClearScopes() void {
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
