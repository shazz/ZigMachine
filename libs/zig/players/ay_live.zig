// --------------------------------------------------------------------------
// The BARD queue's AY device on the output clock (sid_live.zig, the AY range
// $A000..$A0FF): the queue's due writes applied at their output sample, then
// the AY engine (audio_hw.machineAy*: libs/c/ayumi, BARD's native C on the
// board, machine-audio.wasm on the page) rendered up to the next, 44.1 kHz
// stereo straight to the four Paula channels the MP3 player's way (mp3_out.zig:
// a high and a low byte a side). No resampling: one engine frame a stamp.
//
// It also plays an open's silence before its device is known, sample-exact,
// and hands over at a SID reset (render returns there: the .sid engine's
// 22.05 kHz path takes the rest, sid.zig).
// --------------------------------------------------------------------------
const audio = @import("audio_hw");
const out = @import("mp3_out.zig");
const sid_live = @import("sid_live.zig");

/// Stereo frames rendered at most between two writes: they go through song RAM at `chunk_off`.
pub const CHUNK: u32 = 256;

/// Frames 0.. of `bufs` up to `n`, or up to the frame a SID reset is due at. Returns the frames made.
pub fn render(l: *sid_live.Live, bufs: out.Bufs, n: u32, chunk_off: u32) u32 {
    const p: [*]const i16 = @ptrFromInt(audio.SONG_BASE + chunk_off);
    var f: u32 = 0;
    while (f < n) {
        while (l.take()) |e| switch (l.classify(e)) {
            .ay => l.ayAnswer(audio.machineAyWrite(e.addr - sid_live.AY_BASE, e.value) != 0),
            .sid => audio.machineSidWrite(e.addr - sid_live.SID_BASE, e.value),
            .reset => {
                _ = audio.machineSidRaw(e.value);
                return f;
            },
            .none => {},
        };
        const k = l.queue.untilNext(@min(n - f, CHUNK));
        if (l.device == .ay) audio.machineAyRender(audio.songAddr(chunk_off), k);
        for (0..k) |i| {
            const s: [2]i16 = if (l.device == .ay) .{ p[2 * i], p[2 * i + 1] } else .{ 0, 0 };
            out.put(bufs, f + @as(u32, @intCast(i)), out.bytes(s));
        }
        l.queue.advance(k);
        f += k;
    }
    return f;
}
