// --------------------------------------------------------------------------
// audio.wasm entry point
//
// A standalone WASM module instantiated inside the AudioWorklet thread. It owns
// its own linear memory and exposes a tiny C-ABI surface the worklet drives:
//   audioInit()                  - reset engine state
//   audioRender(frames)          - render `frames` stereo samples
//   audioLeftPtr()/audioRightPtr() - pointers to the rendered f32 buffers
//   audioMaxFrames()             - capacity of those buffers
//   audioSetTestTone(on, hz)     - foundation-stage test tone control
// --------------------------------------------------------------------------
const engine_mod = @import("audio/engine.zig");
const Engine = engine_mod.Engine;

var engine: Engine = undefined;

export fn audioInit() void {
    engine.init();
}

export fn audioRender(frames: u32) void {
    engine.render(@intCast(frames));
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

export fn audioSetTestTone(on: bool, hz: f32) void {
    engine.setTestTone(on, hz);
}

// Play the built-in synthetic sample on a Paula channel (proves the sample path).
export fn audioTestSample(ch: u32, on: bool, hz: f32) void {
    engine.testSampleOn(@intCast(ch), on, hz);
}
