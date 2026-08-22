// --------------------------------------------------------------------------
// audio.wasm entry point
//
// A standalone WASM module instantiated inside the AudioWorklet thread. It owns
// its own linear memory and exposes a small C-ABI surface the worklet drives.
//
// Layering:
//   - engine.zig  = the MACHINE: Paula sample channels (+ YM2149 later).
//   - mod.zig     = a ZigOS PLAYER driving the machine. Players are swappable;
//                   people can add their own by driving the same primitives.
// --------------------------------------------------------------------------
const std = @import("std");
const engine_mod = @import("audio/engine.zig");
const Engine = engine_mod.Engine;
const ModPlayer = @import("audio/mod.zig").ModPlayer;
const YmPlayer = @import("audio/ym_player.zig").YmPlayer;

var engine: Engine = undefined;
var mod: ModPlayer = .{};
var ym: YmPlayer = .{};

// Staging RAM for a loaded song (MOD image, or raw YM later). The worklet writes
// the file bytes here, then calls the matching loader.
var song_buf: [1 << 20]u8 = undefined; // 1 MiB

export fn audioInit() void {
    engine.init();
    mod = .{};
    ym = .{};
}

export fn audioRender(frames: u32) void {
    if (ym.active) {
        ym.renderStereo(&engine, @intCast(frames));
    } else if (mod.active) {
        mod.renderStereo(&engine, @intCast(frames));
    } else {
        engine.render(@intCast(frames));
    }
}

export fn audioLeftPtr() [*]f32 {
    return @ptrCast(&engine.left);
}

export fn audioRightPtr() [*]f32 {
    return @ptrCast(&engine.right);
}

export fn audioMaxFrames() u32 {
    return @intCast(engine_mod.MAX_FRAMES);
}

// --- song staging ---
export fn audioSongPtr() [*]u8 {
    return @ptrCast(&song_buf);
}

export fn audioSongCapacity() u32 {
    return @intCast(song_buf.len);
}

// --- MOD player (ZigOS) ---
export fn audioLoadMod(len: u32) bool {
    return mod.load(song_buf[0..@intCast(len)]);
}

export fn audioModPlay() void {
    ym.stop();
    mod.start();
}

export fn audioModStop() void {
    mod.stop();
}

// --- YM player (ZigOS) ---
export fn audioLoadYm(len: u32) bool {
    return ym.load(song_buf[0..@intCast(len)]);
}

export fn audioYmPlay() void {
    mod.stop();
    ym.start();
}

export fn audioYmStop() void {
    ym.stop();
}

// --- raw sample streamer ---
export fn audioPlayRaw(len: u32, rate: f32, is_unsigned: bool) void {
    mod.stop();
    ym.stop();
    const n: usize = @intCast(len);
    if (is_unsigned) {
        var i: usize = 0;
        while (i < n) : (i += 1) song_buf[i] ^= 0x80; // unsigned -> signed
    }
    engine.playRaw(std.mem.bytesAsSlice(i8, song_buf[0..n]), rate);
}

// --- diagnostics ---
export fn audioSetTestTone(on: bool, hz: f32) void {
    engine.setTestTone(on, hz);
}

export fn audioTestSample(ch: u32, on: bool, hz: f32) void {
    engine.testSampleOn(@intCast(ch), on, hz);
}
