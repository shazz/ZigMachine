// --------------------------------------------------------------------------
// The .vgm / .vgz player (Mega Drive / Genesis: YM2612 + SN76489): the file
// staged in song RAM, the VGM engine (audio_hw.machineVgm*: our own chips,
// libs/c/vgm; BARD's native C on the board, machine-audio.wasm on the page)
// renders stereo at its own rate (the YM2612's clock / 288, 26.6 kHz) and
// hands the four Paula channels their bytes the MP3 player's way (a high and a
// low byte a side, x >> 1 exactly), resampled to the mixer's 44.1 kHz with
// mp3_resample.zig's linear arithmetic: machineVgmRenderPaula does both in C
// (libs/c/vgm/zm_vgm_out.c), native on BARD. A .vgz is inflated in place by
// the engine. Song RAM: the file at 0, then the Paula rings (xm_chip BUF_OFFSET).
// The BARD queue's FM device plays through this player too (fm_live.zig): `live` set, the engine's SFX
// device on, the queue's writes fed before each render; the tune is then optional (silent chips without).
// --------------------------------------------------------------------------
const audio = @import("audio_hw");
const ring = @import("xm_ring.zig");
const chip = @import("xm_chip.zig");
const out = @import("mp3_out.zig");
const fm_live = @import("fm_live.zig");
const sid_live = @import("sid_live.zig");

pub const FILE_MAX: u32 = chip.BUF_OFFSET; // a .vgm, or a .vgz and what it inflates to

/// zm_vgm.h's load answers (audioVgmStatus bits 8-15); 5: the file is bigger than the song RAM's room.
pub const Load = enum(u32) { ok = 0, not_vgm = 1, no_chip = 2, truncated = 3, bad_vgz = 4, too_big = 5 };

pub const VgmPlayer = struct {
    active: bool = false,
    load_status: u32 = 0,
    ring_pos: u32 = 0,
    /// The BARD queue's FM device plays through this player (fm_live.zig), its clock from `base`.
    live: ?*sid_live.Live = null,
    base: u32 = 0,
    /// A tune is loaded (with `live`, the player also plays without one).
    tune: bool = false,

    /// Load the `len` bytes staged at SONG_BASE and start them from the top.
    pub fn load(self: *VgmPlayer, len: u32) bool {
        self.stop();
        self.* = .{};
        if (!self.loadTune(len, FILE_MAX)) return false;
        out.setup();
        self.active = true;
        return true;
    }

    /// The FM device's open: a new tune under the queue (`cap`: the song RAM below the queue's block), the
    /// queue playing on; a refused tune leaves the device's chips playing.
    pub fn loadUnderLive(self: *VgmPlayer, len: u32, cap: u32) bool {
        return self.loadTune(len, @min(cap, FILE_MAX));
    }

    fn loadTune(self: *VgmPlayer, len: u32, cap: u32) bool {
        self.load_status = if (len > cap) @intFromEnum(Load.too_big) else audio.machineVgmLoad(audio.songAddr(0), len, cap);
        self.tune = self.load_status == @intFromEnum(Load.ok);
        return self.tune;
    }

    /// The BARD queue's FM device from here: a tune playing keeps playing (the device takes its channels
    /// when the cart says), none: the device's chips, silent until the cart writes.
    pub fn startLive(self: *VgmPlayer, l: *sid_live.Live) void {
        if (!self.active) {
            self.* = .{};
            out.setup();
            self.active = true;
        }
        self.live = l;
        self.base = l.queue.now;
        audio.machineVgmSfxOn(1);
    }

    /// The queue closed: the tune (if any) plays on with every channel, else the player stops.
    pub fn endLive(self: *VgmPlayer) void {
        if (self.live == null) return;
        self.live = null;
        audio.machineVgmSfxOn(0);
        if (!self.tune) self.stop();
    }

    pub fn stop(self: *VgmPlayer) void {
        if (self.live != null) {
            self.live = null;
            audio.machineVgmSfxOn(0);
        }
        if (!self.active) return;
        self.active = false;
        self.tune = false;
        for (0..audio.NUM_CHANNELS) |ch| audio.machinePaulaSetActive(@intCast(ch), 0);
    }

    /// audioVgmStatus: bit 0 a tune playing, bits 8-15 the last load's answer (Load).
    pub fn status(self: *const VgmPlayer) u32 {
        return @as(u32, @intFromBool(self.active and self.tune)) | (self.load_status & 0xFF) << 8;
    }

    pub fn renderStereo(self: *VgmPlayer, frames: usize) void {
        const n: u32 = @intCast(@min(frames, audio.MAX_FRAMES));
        audio.machineClear(n);
        if (n == 0) return;
        if (self.live) |l| fm_live.feed(l, self.base);
        const at0 = ring.place(self.ring_pos, n);
        self.ring_pos = at0 + n;
        // The resampling and the hi/lo split run in the engine's C (libs/c/vgm/zm_vgm_out.c: native on BARD),
        // the same arithmetic as mp3_resample's Linear and mp3_out's bytes.
        var at: [audio.NUM_CHANNELS]u32 = undefined;
        for (&at, 0..) |*p, ch| p.* = audio.songAddr(chip.BUF_OFFSET + ch * ring.FRAMES + at0);
        audio.machineVgmRenderPaula(at[0], at[1], at[2], at[3], n);
        out.trigger(at0, n);
        if (self.live) |l| fm_live.played(l, n);
        audio.machineMixPaula(0, n);
        audio.machineClamp(n);
    }
};
