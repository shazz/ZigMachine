// --------------------------------------------------------------------------
// The .sid player (PSID, Commodore 64): the file staged in song RAM, the SID
// engine (audio_hw.machineSid*: cRSID, libs/c/crsid; BARD's native C on the
// board, machine-audio.wasm on the page) renders 22.05 kHz mono, and the
// samples play on the four Paula channels the MP3 player's way (mp3_out.zig:
// a high and a low byte a side, x >> 1 exactly), converted to the mixer's
// 44.1 kHz linearly (mp3_resample.zig: every other sample is a midpoint).
// RSID files (real C64 programs, ~2x BARD) are refused at load (status 2).
// Song RAM: the .sid at 0, the engine's 22.05 kHz chunk after it, then the
// Paula rings (xm_chip BUF_OFFSET).
// --------------------------------------------------------------------------
const audio = @import("audio_hw");
const ring = @import("xm_ring.zig");
const chip = @import("xm_chip.zig");
const rs = @import("mp3_resample.zig");
const out = @import("mp3_out.zig");
const sid_live = @import("sid_live.zig");

pub const RATE: u32 = 22050;
pub const FILE_MAX: u32 = 0x10000 + 0x7C + 2; // a C64's 64 KiB, its load address and the v2 header
const CHUNK_OFF: u32 = 0x10200; // after the file, 2-aligned
pub const CHUNK: u32 = 512; // engine samples a call
pub const LIVE_CHUNK: u32 = 128; // SID live: the most rendered ahead between two writes
comptime {
    if (CHUNK_OFF + 2 * CHUNK > chip.BUF_OFFSET) @compileError("the SID player's song RAM overlaps the Paula rings");
}

/// zm_sid.h's load answers (audioSidStatus bits 8-15).
pub const Load = enum(u32) { ok = 0, not_sid = 1, rsid = 2, bad_length = 3 };

pub const SidPlayer = struct {
    active: bool = false,
    load_status: u32 = 0,
    conv: rs.Linear = rs.Linear.init(RATE),
    chunk_n: u32 = 0,
    chunk_at: u32 = 0,
    ring_pos: u32 = 0,
    /// SID live (the BARD queue): no file, the cart's timed register writes (sid_live.zig).
    live: ?*sid_live.Live = null,

    /// Load the `len` bytes staged at SONG_BASE and start `tune` (1-based, 0 = the file's default).
    pub fn load(self: *SidPlayer, len: u32, tune: u32) bool {
        self.stop();
        self.* = .{};
        self.load_status = if (len > FILE_MAX) @intFromEnum(Load.bad_length) else audio.machineSidLoad(audio.songAddr(0), len, tune);
        if (self.load_status != @intFromEnum(Load.ok)) return false;
        out.setup();
        self.active = true;
        return true;
    }

    /// SID live: play the cart's register writes from `l` (silent until its first reset).
    pub fn startLive(self: *SidPlayer, l: *sid_live.Live) void {
        self.stop();
        self.* = .{};
        out.setup();
        self.live = l;
        self.active = true;
    }

    pub fn stop(self: *SidPlayer) void {
        if (!self.active) return;
        self.active = false;
        for (0..audio.NUM_CHANNELS) |ch| audio.machinePaulaSetActive(@intCast(ch), 0);
    }

    /// audioSidStatus: bit 0 playing, bits 8-15 the last load's answer (Load).
    pub fn status(self: *const SidPlayer) u32 {
        return @as(u32, @intFromBool(self.active)) | (self.load_status & 0xFF) << 8;
    }

    pub fn renderStereo(self: *SidPlayer, frames: usize) void {
        const n: u32 = @intCast(@min(frames, audio.MAX_FRAMES));
        audio.machineClear(n);
        if (n == 0) return;
        const at0 = ring.place(self.ring_pos, n);
        self.ring_pos = at0 + n;
        const bufs = out.buffers(at0);
        for (0..n) |f| out.put(bufs, @intCast(f), out.bytes(self.next()));
        out.trigger(at0, n);
        audio.machineMixPaula(0, n);
        audio.machineClamp(n);
    }

    /// The next 44.1 kHz output sample (mono on both sides).
    fn next(self: *SidPlayer) [2]i16 {
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

    fn source(self: *SidPlayer) [2]i16 {
        const p: [*]const i16 = @ptrFromInt(audio.SONG_BASE + CHUNK_OFF);
        if (self.chunk_at >= self.chunk_n) {
            if (self.live) |l| {
                self.chunk_n = liveChunk(l);
            } else {
                audio.machineSidRender(audio.songAddr(CHUNK_OFF), CHUNK);
                self.chunk_n = CHUNK;
            }
            self.chunk_at = 0;
        }
        const v = p[self.chunk_at];
        self.chunk_at += 1;
        return .{ v, v };
    }
};

/// SID live: the writes now due applied, then the engine rendered up to the next one.
fn liveChunk(l: *sid_live.Live) u32 {
    while (l.take()) |e| switch (l.classify(e)) {
        .sid => audio.machineSidWrite(e.addr - sid_live.SID_BASE, e.value),
        .reset => _ = audio.machineSidRaw(e.value),
        .none => {},
    };
    const n = l.chunk(LIVE_CHUNK);
    if (l.engine_on) {
        audio.machineSidRender(audio.songAddr(CHUNK_OFF), n);
    } else {
        const p: [*]i16 = @ptrFromInt(audio.SONG_BASE + CHUNK_OFF);
        @memset(p[0..n], 0);
    }
    l.advance(n);
    return n;
}
