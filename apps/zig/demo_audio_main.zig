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
const SndhPlayer = players.SndhPlayer;

var mod: ModPlayer = .{};
var ym: YmPlayer = .{};
var sndh: SndhPlayer = .{};
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
    sndh = .{};
    current_mode = 0;
}

export fn audioRender(frames: u32) void {
    const n: usize = @intCast(frames);
    if (sndh.active) {
        sndh.renderStereo(n);
    } else if (ym.active) {
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

// --- SNDH player (the tune's own 68000 code, on Musashi, driving the PSG) ---
export fn audioLoadSndh(len: u32) bool {
    return sndh.load(len);
}
export fn audioSndhPlay(tune: u8) void {
    mod.stop();
    ym.stop();
    audio.machinePaulaClearScopes();
    sndh.start(tune);
    current_mode = if (sndh.active) 4 else 0;
}
export fn audioSndhStop() void {
    sndh.stop();
    if (current_mode == 4) current_mode = 0;
}

/// Stop EVERYTHING — the audio half of a machine reset.
///
/// The host calls this on every cart instantiation, next to romReset(). A screen
/// cannot switch its own tune off on the way out (it is already gone by then), so
/// the machine reclaims the sound chip the way it reclaims the ROM's handles.
/// Stopping every player rather than "the one that was playing" is deliberate:
/// the host would have to track that, and a host that tracks state gets it wrong.
export fn audioReset() void {
    mod.stop();
    ym.stop();
    sndh.stop();
    audio.machineAudioReset();
    current_mode = 0;
}
/// Where a replay call gave up, when a tune refuses to run. 0 means it ran.
export fn audioSndhStuckPc() u32 {
    return players.sndhStuckPc();
}
/// How far into the SNDH we are, in milliseconds (0 when none is playing).
export fn audioSndhPositionMs() u32 {
    return if (sndh.active) sndh.positionMs() else 0;
}
/// How fast MFP timer t (0=A..3=D) is programmed, in Hz (0 = stopped).
export fn audioSndhTimerRate(t: u32) u32 {
    return players.sndhTimerRate(t);
}
/// The last trap the little TOS did not know how to answer, (trap << 16) | fn.
export fn audioSndhUnhandledTrap() u32 {
    return players.sndhUnhandledTrap();
}
/// How many subtunes the loaded tune carries (0 when nothing is loaded).
export fn audioSndhSubtunes() u8 {
    return if (sndh.info.hz == 0) 0 else sndh.info.subtunes;
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

// Silence the stream. The ring is a LOOPING Paula channel, so it keeps replaying
// whatever it holds until the channel is switched off — draining is not something
// it does on its own.
export fn audioStreamStop() void {
    audio.machinePaulaSetActive(0, 0);
    audio.machinePaulaSetVolume(0, 0.0);
    const buf: [*]u8 = @ptrFromInt(audio.SONG_BASE);
    var i: usize = 0;
    while (i < STREAM_RING) : (i += 1) buf[i] = 0;
    audio.machinePaulaClearScopes();
    current_mode = 0;
}

// --- streaming raw sample (Amiga-style refill-ahead ring) ---
// A Paula channel loops forever over a fixed ring at the start of song RAM; the
// host keeps writing fresh signed-8-bit samples ahead of the read cursor, paced
// to the play rate, so samples far larger than SONG_CAP can play.
pub const STREAM_RING: usize = 32768; // ring size, at SONG_BASE

export fn audioStreamStart(rate: f32) void {
    mod.stop();
    ym.stop();
    audio.machinePaulaClearScopes();
    // Zero the ring so an under-fed start is silence, not garbage.
    const buf: [*]u8 = @ptrFromInt(audio.SONG_BASE);
    var i: usize = 0;
    while (i < STREAM_RING) : (i += 1) buf[i] = 0;
    var ch: u32 = 1;
    while (ch < audio.NUM_CHANNELS) : (ch += 1) audio.machinePaulaSetActive(ch, 0);
    audio.machinePaulaTrigger(0, audio.songAddr(0), STREAM_RING, 0, STREAM_RING, 0.0); // loop the whole ring
    audio.machinePaulaSetStep(0, @intFromFloat(rate / audio.SAMPLE_RATE * audio.FRAC_ONE));
    audio.machinePaulaSetVolume(0, 0.9);
    current_mode = 3;
}

