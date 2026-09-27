// --------------------------------------------------------------------------
// demo-audio.wasm: the raw 8-bit sample players, the simplest on the Paula
// primitive -- a whole sample looped on channel 0, or a ring the host keeps
// refilling ahead of the read cursor. Split from demo_audio_main.zig, whose
// players and mode they share.
// --------------------------------------------------------------------------
const audio = @import("audio_hw");
const m = @import("root");

// --- a whole sample, looped ---
export fn audioPlayRaw(len: u32, rate: f32, is_unsigned: bool) void {
    m.mod.stop();
    m.ym.stop();
    audio.machinePaulaClearScopes();

    const n: usize = @intCast(len);
    if (is_unsigned) {
        const buf: [*]u8 = @ptrFromInt(audio.SONG_BASE);
        for (buf[0..n]) |*b| b.* ^= 0x80; // unsigned -> signed
    }
    // Play on channel 0, looped, silence the rest.
    silenceAllBut0();
    audio.machinePaulaTrigger(0, audio.songAddr(0), len, 0, len, 0.0);
    audio.machinePaulaSetStep(0, @intFromFloat(rate / audio.SAMPLE_RATE * audio.FRAC_ONE));
    audio.machinePaulaSetVolume(0, 0.9);
    m.current_mode = 3;
}

// Silence the stream. The ring is a LOOPING Paula channel, so it keeps replaying
// whatever it holds until the channel is switched off — draining is not something
// it does on its own.
export fn audioStreamStop() void {
    audio.machinePaulaSetActive(0, 0);
    audio.machinePaulaSetVolume(0, 0.0);
    @memset(ring(), 0);
    audio.machinePaulaClearScopes();
    m.current_mode = 0;
}

// --- streaming raw sample (Amiga-style refill-ahead ring) ---
// A Paula channel loops forever over a fixed ring at the start of song RAM; the
// host keeps writing fresh signed-8-bit samples ahead of the read cursor, paced
// to the play rate, so samples far larger than SONG_CAP can play.
const STREAM_RING = m.STREAM_RING; // at SONG_BASE

export fn audioStreamStart(rate: f32) void {
    m.mod.stop();
    m.ym.stop();
    audio.machinePaulaClearScopes();
    // Zero the ring so an under-fed start is silence, not garbage.
    @memset(ring(), 0);
    silenceAllBut0();
    audio.machinePaulaTrigger(0, audio.songAddr(0), STREAM_RING, 0, STREAM_RING, 0.0); // loop the whole ring
    audio.machinePaulaSetStep(0, @intFromFloat(rate / audio.SAMPLE_RATE * audio.FRAC_ONE));
    audio.machinePaulaSetVolume(0, 0.9);
    m.current_mode = 3;
}

fn ring() []u8 {
    const p: [*]u8 = @ptrFromInt(audio.SONG_BASE);
    return p[0..STREAM_RING];
}

fn silenceAllBut0() void {
    for (1..audio.NUM_CHANNELS) |ch| audio.machinePaulaSetActive(@intCast(ch), 0);
}
