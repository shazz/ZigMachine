// --------------------------------------------------------------------------
// The klystrack (.kt) player: an OPEN ZigOS player, klystron's cyd synth and
// music.c sequencer in integer Zig (kt_core.zig, bit-exact against upstream),
// on the four Paula channels the MOD and XM players use. So it runs on the
// sealed audio chip in the browser and on BARD (the FPGA sound CPU) alike.
//
// The output: cyd mixes 16-bit stereo at 22050 Hz, the klystrack cart's rate;
// each sample is held for two 44.1 kHz frames. Paula is 8-bit, so each side
// takes two channels, its high byte at volume 511/256 and its low byte at
// 2/256, hard left / hard right: s = 256 h + l plays as (511 h + 2 l) / 65536,
// s / 32768 to within 1/512 of gain and half a 16-bit step, a full-scale
// 16-bit side from 8-bit channels with no machine change (both volumes are on
// the audio core's 1/256 grid, so the board mixes the browser's integers).
// The rings and their placement are XM's (xm_ring.zig: a block must outlive
// the board's lead). The scope view is the MOD's (mode 1): channels 0 and 1
// show the waveform, 2 and 3 its low bytes.
//
// Memory: the song's tables, cyd's FX delay lines (2 s of reverb a bus) and
// the render block live in song RAM past the file, below the Paula rings;
// a song that does not fit is refused (kt_arena.zig).
// --------------------------------------------------------------------------
const audio = @import("audio_hw");
const core = @import("kt_core"); // its own module, built for speed (build.zig)
const rd = core.read;
const ring = @import("xm_ring.zig");
const chip = @import("xm_chip.zig");

pub const VOL_HI: f32 = 511.0 / 256.0;
pub const VOL_LO: f32 = 2.0 / 256.0;
const PAN = [audio.NUM_CHANNELS]f32{ -1.0, 1.0, -1.0, 1.0 }; // hi L, hi R, lo L, lo R
/// Core samples rendered at a time: 1 KiB of song RAM for them, where a whole 4096-frame block took
/// 8 KiB, so the core's 9 KiB mix (kt_block.zig BLOCK 128) and this stay inside the 16 KiB the
/// klystrack cart counts for them (apps/ports/klystrack/kestrel_bard.c kt_fits).
const PCM_CHUNK = 256;

pub const KtPlayer = struct {
    core: core.Core = .{},
    active: bool = false,
    pcm: []i16 = &.{}, // one block of core samples, interleaved
    held: [2]i16 = .{ 0, 0 }, // a core sample whose second frame is still to play
    held_pending: bool = false,
    ring_pos: u32 = 0,

    /// Parse the `len` bytes staged at song RAM's start; its tables go after it.
    pub fn load(self: *KtPlayer, len: u32) rd.Error!void {
        self.active = false;
        if (len > chip.BUF_OFFSET) return error.TooLarge;
        const base: [*]u8 = @ptrFromInt(audio.SONG_BASE);
        const from = (len + 7) & ~@as(u32, 7);
        if (from >= chip.BUF_OFFSET) return error.TooLarge;
        try self.core.load(base[0..len], base[from..chip.BUF_OFFSET]);
    }

    /// Start the loaded song at sequence row `position` (0: its start), at the cart's 22050 Hz.
    pub fn start(self: *KtPlayer, position: u16) bool {
        self.core.startAt(core.RATE, position) catch return false;
        self.pcm = self.core.arena.alloc(i16, 2 * PCM_CHUNK) catch return false;
        self.held_pending = false;
        self.ring_pos = 0;
        for (0..audio.NUM_CHANNELS) |ch| {
            audio.machinePaulaSetStep(@intCast(ch), 1 << 16);
            audio.machinePaulaSetVolume(@intCast(ch), if (ch < 2) VOL_HI else VOL_LO);
        }
        self.active = true;
        return true;
    }

    /// Silence the channels, but only if this player was playing.
    pub fn stop(self: *KtPlayer) void {
        if (!self.active) return;
        self.active = false;
        for (0..audio.NUM_CHANNELS) |ch| audio.machinePaulaSetActive(@intCast(ch), 0);
    }

    pub fn renderStereo(self: *KtPlayer, frames: usize) void {
        const n: u32 = @intCast(@min(frames, audio.MAX_FRAMES));
        audio.machineClear(n);
        if (n == 0) return;
        const at0 = ring.place(self.ring_pos, n);
        self.ring_pos = at0 + n;
        var bufs: [audio.NUM_CHANNELS][*]i8 = undefined;
        for (&bufs, 0..) |*b, ch| b.* = @ptrFromInt(audio.SONG_BASE + chip.BUF_OFFSET + ch * ring.FRAMES + at0);
        var f: u32 = 0;
        if (self.held_pending) {
            split(bufs, 0, self.held);
            f = 1;
        }
        const fresh = (n - f + 1) / 2; // new core samples this block
        self.held_pending = false;
        var done: usize = 0;
        while (done < fresh) { // PCM_CHUNK at a time: the core's output does not depend on how it is cut
            const m: usize = @min(fresh - done, PCM_CHUNK); // typed: @min with a constant narrows (u9 here), and 2 * 256 overflows u9
            self.core.render(self.pcm[0 .. 2 * m]);
            for (0..m) |k| {
                const smp = [2]i16{ self.pcm[2 * k], self.pcm[2 * k + 1] };
                const b = bytes(smp); // once for the sample's two frames
                put(bufs, f, b);
                f += 1;
                if (f < n) {
                    put(bufs, f, b);
                    f += 1;
                } else { // only the last sample, when the block has an odd number of frames left
                    self.held = smp;
                    self.held_pending = true;
                }
            }
            done += m;
        }
        for (0..audio.NUM_CHANNELS) |ch| {
            const at = chip.BUF_OFFSET + ch * ring.FRAMES + at0;
            audio.machinePaulaTrigger(@intCast(ch), audio.songAddr(at), n, 0, 0, PAN[ch]);
        }
        audio.machineMixPaula(0, n);
        audio.machineClamp(n);
    }
};

/// Frame `f` of the four channels: each side's high and low byte (s = 256 h + l).
fn split(bufs: [audio.NUM_CHANNELS][*]i8, f: u32, smp: [2]i16) void {
    put(bufs, f, bytes(smp));
}

/// A sample's four channel bytes: hi L, hi R, lo L, lo R.
inline fn bytes(smp: [2]i16) [audio.NUM_CHANNELS]i8 {
    var b: [audio.NUM_CHANNELS]i8 = undefined;
    for (0..2) |side| {
        const s: i32 = @min(smp[side], 32639); // 256 * 127 + 127: the top a signed high byte holds
        const h = (s + 128) >> 8;
        b[side] = @intCast(h);
        b[2 + side] = @intCast(s - (h << 8));
    }
    return b;
}

inline fn put(bufs: [audio.NUM_CHANNELS][*]i8, f: u32, b: [audio.NUM_CHANNELS]i8) void {
    for (0..audio.NUM_CHANNELS) |ch| bufs[ch][f] = b[ch];
}
