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
const engine_mod = @import("audio/engine.zig");
const Engine = engine_mod.Engine;
const ModPlayer = @import("audio/mod.zig").ModPlayer;

var engine: Engine = undefined;
var mod: ModPlayer = .{};

// Staging RAM for a loaded song (MOD image, or raw YM later). The worklet writes
// the file bytes here, then calls the matching loader.
var song_buf: [1 << 20]u8 = undefined; // 1 MiB

export fn audioInit() void {
    engine.init();
    mod = .{};
}

export fn audioRender(frames: u32) void {
    if (mod.active) {
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
    mod.start();
}

export fn audioModStop() void {
    mod.stop();
}

// --- diagnostics ---
export fn audioSetTestTone(on: bool, hz: f32) void {
    engine.setTestTone(on, hz);
}

export fn audioTestSample(ch: u32, on: bool, hz: f32) void {
    engine.testSampleOn(@intCast(ch), on, hz);
}
