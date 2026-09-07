// --------------------------------------------------------------------------
// demo-audio.wasm entry point (OPEN — the coder's audio binary).
//
// The ZigOS players (MOD / YM / raw sample) + the worklet-facing control API.
// Runs on the AudioWorklet thread, sharing ONE memory with the sealed
// machine-audio.wasm; it drives the chips only through sdk/audio.zig. The worklet
// writes song files into the shared song RAM (audioSongPtr) and calls audioLoad*
// / audioRender; the chip's stereo buffers + scopes are read from machine-audio.
// --------------------------------------------------------------------------
const std = @import("std");
const audio = @import("audio_hw"); // sealed audio chip ABI (named module)
const players = @import("players"); // open ZigOS players (named module)
const ModPlayer = players.ModPlayer;
const YmPlayer = players.YmPlayer;

var mod: ModPlayer = .{};
var ym: YmPlayer = .{};
// Active player: 0 none, 1 MOD, 2 YM, 3 raw sample. Drives the scope view type.
var current_mode: u8 = 0;

fn songSlice(len: u32) []const u8 {
    const p: [*]const u8 = @ptrFromInt(audio.SONG_BASE);
    return p[0..@intCast(len)];
}

export fn audioInit() void {
    audio.machineAudioInit();
    mod = .{};
    ym = .{};
    current_mode = 0;
}

export fn audioRender(frames: u32) void {
    const n: usize = @intCast(frames);
    if (ym.active) {
        ym.renderStereo(n);
    } else if (mod.active) {
        mod.renderStereo(n);
    } else {
        // Nothing sequencing: mix any live Paula channels (the raw streamer) —
        // or silence. Mirrors the pre-seal engine.render() Paula path.
        const m = @min(n, audio.MAX_FRAMES);
        audio.machineClear(@intCast(m));
        audio.machineMixPaula(0, @intCast(m));
        audio.machineClamp(@intCast(m));
    }
}

// --- song staging (shared song RAM) ---
export fn audioSongPtr() [*]u8 {
    return @ptrFromInt(audio.SONG_BASE);
}
export fn audioSongCapacity() u32 {
    return @intCast(audio.SONG_CAP);
}

// Active player mode (0 none, 1 MOD, 2 YM, 3 sample). Drives the scope view.
export fn audioMode() u8 {
    return current_mode;
}

// --- MOD player ---
export fn audioLoadMod(len: u32) bool {
    return mod.load(songSlice(len));
}
export fn audioModPlay() void {
    ym.stop();
    audio.machinePaulaClearScopes();
    mod.start();
    current_mode = 1;
}
export fn audioModStop() void {
    mod.stop();
    if (current_mode == 1) current_mode = 0;
}

// --- YM player ---
export fn audioLoadYm(len: u32) bool {
    return ym.load(songSlice(len));
}
export fn audioYmPlay() void {
    mod.stop();
    audio.machinePaulaClearScopes();
    ym.start();
    current_mode = 2;
}
export fn audioYmStop() void {
    ym.stop();
    if (current_mode == 2) current_mode = 0;
}

// --- raw 8-bit sample streamer (the simplest player on the Paula primitive) ---
export fn audioPlayRaw(len: u32, rate: f32, is_unsigned: bool) void {
    mod.stop();
    ym.stop();
    audio.machinePaulaClearScopes();

    const n: usize = @intCast(len);
    if (is_unsigned) {
        const buf: [*]u8 = @ptrFromInt(audio.SONG_BASE);
        var i: usize = 0;
        while (i < n) : (i += 1) buf[i] ^= 0x80; // unsigned -> signed
    }
    // Play on channel 0, looped, silence the rest.
    var ch: u32 = 1;
    while (ch < audio.NUM_CHANNELS) : (ch += 1) audio.machinePaulaSetActive(ch, 0);
    audio.machinePaulaTrigger(0, audio.songAddr(0), len, 0, len, 0.0);
    audio.machinePaulaSetStep(0, @intFromFloat(rate / audio.SAMPLE_RATE * audio.FRAC_ONE));
    audio.machinePaulaSetVolume(0, 0.9);
    current_mode = 3;
}
