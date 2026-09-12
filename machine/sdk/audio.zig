// --------------------------------------------------------------------------
// ZigMachine — published AUDIO hardware API header.
//
// The sealed machine-audio.wasm implements Paula (4 sample channels) + a YM2149
// PSG. The OPEN players (MOD / YM / sample, in the demo-audio module) drive the
// chips ONLY through these extern setters + the shared song RAM — mirroring how
// the video machine exposes framebuffers/registers. Both audio modules share ONE
// WebAssembly.Memory on the AudioWorklet thread.
//
// Data flow per sub-block (driven by the open player's render loop):
//   machineClear(n) -> [player writes chip regs] -> machineMixPaula/RenderYm(off,len)
//   -> machineClamp(n).  The worklet then reads the stereo buffers.
// --------------------------------------------------------------------------

// --- audio constants (must match src/audio/engine.zig — the sealed chips) ---
pub const SAMPLE_RATE: f32 = 44100.0;
pub const MAX_FRAMES: usize = 4096;
pub const NUM_CHANNELS: usize = 4;
pub const SCOPE_LEN: usize = 128;
pub const FRAC_ONE: f32 = 65536.0; // Paula fixed-point (16 fractional bits)

// --- reserved audio memory (own shared memory on the worklet thread) ---
//   [0x000000..0x100000) machine-audio data + stack (chips, buffers, scopes)
//   [0x100000..0x200000) demo-audio data + stack     (players)
//   [0x200000..0x300000) song RAM (host writes files here; player + chip read)
pub const SONG_BASE: usize = 0x200000;
pub const SONG_CAP: usize = 0x100000; // 1 MiB
pub const AUDIO_PAGES: u32 = 48; // 3 MiB shared, initial == max
pub const DEMO_GLOBAL_BASE: u64 = 0x100000;

pub const ZM_AUDIO_VERSION: u32 = 0x0001_0100; // 1.1.0 — added machineAudioReset

// --- sealed chip control surface (implemented in machine-audio.wasm) ---
pub extern fn machineAudioInit() void;
pub extern fn machineClear(n: u32) void; // zero the stereo bus [0,n)
pub extern fn machineClamp(n: u32) void; // clamp the stereo bus [0,n) to [-1,1]
pub extern fn machineMixPaula(off: u32, len: u32) void; // mix 4 sample channels into [off,off+len)
pub extern fn machineRenderYm(off: u32, len: u32) void; // render the PSG into [off,off+len)
pub extern fn machineYmWrite(reg: u32, val: u32) void; // write a YM register (retriggers env on r13)
pub extern fn machinePaulaClearScopes() void;
pub extern fn machineAudioReset() void; // silence the chip when a program ends

// One Paula channel is (re)started from song RAM; step/volume/pan/pos are then
// tweaked per row/tick, exactly as the pre-seal player poked the Channel struct.
pub extern fn machinePaulaTrigger(ch: u32, data_abs: u32, data_len: u32, loop_start: u32, loop_len: u32, pan: f32) void;
pub extern fn machinePaulaSetStep(ch: u32, step: u32) void;
pub extern fn machinePaulaSetVolume(ch: u32, vol: f32) void;
pub extern fn machinePaulaSetPan(ch: u32, pan: f32) void;
pub extern fn machinePaulaSetPos(ch: u32, pos_samples: u32) void;
pub extern fn machinePaulaSetActive(ch: u32, on: u32) void;

// Absolute linear-memory address of a byte offset within song RAM.
pub inline fn songAddr(offset: usize) u32 {
    return @intCast(SONG_BASE + offset);
}
