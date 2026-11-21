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
// --------------------------------------------------------------------------
const audio = @import("audio_hw");
const ring = @import("xm_ring.zig");
const chip = @import("xm_chip.zig");
const out = @import("mp3_out.zig");

pub const FILE_MAX: u32 = chip.BUF_OFFSET; // a .vgm, or a .vgz and what it inflates to

/// zm_vgm.h's load answers (audioVgmStatus bits 8-15); 5: the file is bigger than the song RAM's room.
pub const Load = enum(u32) { ok = 0, not_vgm = 1, no_chip = 2, truncated = 3, bad_vgz = 4, too_big = 5 };

pub const VgmPlayer = struct {
    active: bool = false,
    load_status: u32 = 0,
    ring_pos: u32 = 0,

    /// Load the `len` bytes staged at SONG_BASE and start them from the top.
    pub fn load(self: *VgmPlayer, len: u32) bool {
        self.stop();
        self.* = .{};
        self.load_status = if (len > FILE_MAX) @intFromEnum(Load.too_big) else audio.machineVgmLoad(audio.songAddr(0), len, FILE_MAX);
        if (self.load_status != @intFromEnum(Load.ok)) return false;
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
        // The resampling and the hi/lo split run in the engine's C (libs/c/vgm/zm_vgm_out.c: native on BARD),
        // the same arithmetic as mp3_resample's Linear and mp3_out's bytes.
        var at: [audio.NUM_CHANNELS]u32 = undefined;
        for (&at, 0..) |*p, ch| p.* = audio.songAddr(chip.BUF_OFFSET + ch * ring.FRAMES + at0);
        audio.machineVgmRenderPaula(at[0], at[1], at[2], at[3], n);
        out.trigger(at0, n);
        audio.machineMixPaula(0, n);
        audio.machineClamp(n);
    }
};
