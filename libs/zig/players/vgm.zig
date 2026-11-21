// --------------------------------------------------------------------------
// The .vgm / .vgz player (Mega Drive / Genesis: YM2612 + SN76489): the file
// staged in song RAM, the VGM engine (audio_hw.machineVgm*: our own chips,
// libs/c/vgm; BARD's native C on the board, machine-audio.wasm on the page)
// renders stereo at its own rate (the YM2612's clock / 288, 26.6 kHz), and the
// samples play on the four Paula channels the MP3 player's way (mp3_out.zig:
// a high and a low byte a side, x >> 1 exactly), converted to the mixer's
// 44.1 kHz linearly (mp3_resample.zig). A .vgz is inflated in place by the
// engine, into the room before the chunk. Song RAM: the file at 0, the
// engine's stereo chunk at CHUNK_OFF, then the Paula rings (xm_chip BUF_OFFSET).
// --------------------------------------------------------------------------
const audio = @import("audio_hw");
const ring = @import("xm_ring.zig");
const chip = @import("xm_chip.zig");
const rs = @import("mp3_resample.zig");
const out = @import("mp3_out.zig");

pub const CHUNK: u32 = 256; // engine frames a call
pub const CHUNK_OFF: u32 = chip.BUF_OFFSET - 4 * CHUNK; // the stereo chunk, just under the Paula rings
pub const FILE_MAX: u32 = CHUNK_OFF; // a .vgm, or a .vgz and what it inflates to
comptime {
    if (CHUNK_OFF % 4 != 0) @compileError("the VGM chunk must be 4-aligned");
}

/// zm_vgm.h's load answers (audioVgmStatus bits 8-15); 5: the file is bigger than the song RAM's room.
pub const Load = enum(u32) { ok = 0, not_vgm = 1, no_chip = 2, truncated = 3, bad_vgz = 4, too_big = 5 };

pub const VgmPlayer = struct {
    active: bool = false,
    load_status: u32 = 0,
    conv: rs.Linear = rs.Linear.init(26633),
    chunk_n: u32 = 0,
    chunk_at: u32 = 0,
    ring_pos: u32 = 0,

    /// Load the `len` bytes staged at SONG_BASE and start them from the top.
    pub fn load(self: *VgmPlayer, len: u32) bool {
        self.stop();
        self.* = .{};
        self.load_status = if (len > FILE_MAX) @intFromEnum(Load.too_big) else audio.machineVgmLoad(audio.songAddr(0), len, FILE_MAX);
        if (self.load_status != @intFromEnum(Load.ok)) return false;
        self.conv = rs.Linear.init(audio.machineVgmRate());
        out.setup();
        self.active = true;
        return true;
    }

    pub fn stop(self: *VgmPlayer) void {
        if (!self.active) return;
        self.active = false;
        for (0..audio.NUM_CHANNELS) |ch| audio.machinePaulaSetActive(@intCast(ch), 0);
    }

    /// audioVgmStatus: bit 0 playing, bits 8-15 the last load's answer (Load).
    pub fn status(self: *const VgmPlayer) u32 {
        return @as(u32, @intFromBool(self.active)) | (self.load_status & 0xFF) << 8;
    }

    pub fn renderStereo(self: *VgmPlayer, frames: usize) void {
        const n: u32 = @intCast(@min(frames, audio.MAX_FRAMES));
        audio.machineClear(n);
        if (n == 0) return;
        const at0 = ring.place(self.ring_pos, n);
        self.ring_pos = at0 + n;
        const bufs = out.buffers(at0);
        var f: u32 = 0;
        while (f < n) : (f += 1) out.put(bufs, f, out.bytes(self.next()));
        out.trigger(at0, n);
        audio.machineMixPaula(0, n);
        audio.machineClamp(n);
    }

    /// The next 44.1 kHz output frame.
    fn next(self: *VgmPlayer) [2]i16 {
        const c = &self.conv;
        if (!c.primed) { // no delay: the first output sample is the first engine sample
            c.push(self.source());
            c.push(self.source());
            c.primed = true;
        }
        const s = c.sample();
        var k = c.advance();
        while (k > 0) : (k -= 1) c.push(self.source());
        return s;
    }

    fn source(self: *VgmPlayer) [2]i16 {
        const p: [*]const i16 = @ptrFromInt(audio.SONG_BASE + CHUNK_OFF);
        if (self.chunk_at >= self.chunk_n) {
            audio.machineVgmRender(audio.songAddr(CHUNK_OFF), CHUNK);
            self.chunk_n = CHUNK;
            self.chunk_at = 0;
        }
        const i = 2 * self.chunk_at;
        self.chunk_at += 1;
        return .{ p[i], p[i + 1] };
    }
};
