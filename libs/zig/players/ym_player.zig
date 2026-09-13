const std = @import("std");
const audio = @import("audio_hw");

// --------------------------------------------------------------------------
// DEPRECATED (Matt, 2026-09-13): a screen's music is an SNDH (the tune's real
// 68000 replay code, libs/zig/players/sndh_player.zig), never a .ym/.ymraw dump.
// A dump samples the chip only once per frame, so mid-frame effects (SID voices,
// digidrums, sample playback through the volume DAC) are lost or turn into
// bleeps. Use this player ONLY as the last resort, when no SNDH of the tune
// exists after a real search of prototypes/sndh_lf/. Say so in the scene's music
// comment, with the best SNDH score. Do not add features to it.
//
// YM register-dump player (YM5!/YM6!) — an OPEN ZigOS player driving the SEALED
// YM2149 chip. Parses a depacked .ym image from the shared song RAM and writes
// the 14 registers to the chip once per player frame (typically 50 Hz), sample-
// accurately, via the sdk/audio.zig chip API.
//
// Digidrums are not handled yet (tunes with drums > 0 will miss those hits).
// --------------------------------------------------------------------------

fn be16(d: []const u8, o: usize) u16 {
    return (@as(u16, d[o]) << 8) | d[o + 1];
}
fn be32(d: []const u8, o: usize) u32 {
    return (@as(u32, d[o]) << 24) | (@as(u32, d[o + 1]) << 16) | (@as(u32, d[o + 2]) << 8) | d[o + 3];
}

pub const YmPlayer = struct {
    reg_data: []const u8 = &.{},
    nb_frames: u32 = 0,
    interleaved: bool = true,
    loop_frame: u32 = 0,

    active: bool = false,
    frame: u32 = 0,
    samples_per_frame: u32 = 882,
    frame_acc: u32 = 0,

    pub fn load(self: *YmPlayer, data: []const u8) bool {
        self.* = .{};
        if (data.len < 34) return false;
        if (!std.mem.eql(u8, data[0..4], "YM5!") and !std.mem.eql(u8, data[0..4], "YM6!")) return false;

        self.nb_frames = be32(data, 12);
        const attr = be32(data, 16);
        self.interleaved = (attr & 1) != 0;
        const ndrums = be16(data, 20);
        const rate = be16(data, 26);
        self.loop_frame = be32(data, 28);
        const fut = be16(data, 32);

        var off: usize = 34 + fut;
        var d: usize = 0;
        while (d < ndrums) : (d += 1) {
            if (off + 4 > data.len) return false;
            off += 4 + be32(data, off);
        }
        var s: usize = 0;
        while (s < 3) : (s += 1) {
            while (off < data.len and data[off] != 0) off += 1;
            off += 1; // the null
        }

        const needed = @as(usize, self.nb_frames) * 16;
        if (off + needed > data.len) return false;
        self.reg_data = data[off .. off + needed];

        const r: f32 = @floatFromInt(if (rate == 0) 50 else rate);
        self.samples_per_frame = @intFromFloat(audio.SAMPLE_RATE / r);
        return true;
    }

    pub fn start(self: *YmPlayer) void {
        self.active = true;
        self.frame = 0;
        self.frame_acc = 0;
    }

    pub fn stop(self: *YmPlayer) void {
        self.active = false;
    }

    fn regValue(self: *YmPlayer, reg: usize, frame: u32) u8 {
        const idx = if (self.interleaved)
            reg * self.nb_frames + frame
        else
            frame * 16 + reg;
        return self.reg_data[idx];
    }

    fn writeFrame(self: *YmPlayer) void {
        if (self.frame >= self.nb_frames) {
            self.frame = if (self.loop_frame < self.nb_frames) self.loop_frame else 0;
        }
        var reg: usize = 0;
        while (reg < 14) : (reg += 1) {
            audio.machineYmWrite(@intCast(reg), self.regValue(reg, self.frame));
        }
        self.frame += 1;
    }

    pub fn renderStereo(self: *YmPlayer, frames: usize) void {
        const n = @min(frames, audio.MAX_FRAMES);
        audio.machineClear(@intCast(n));
        var off: usize = 0;
        while (off < n) {
            if (self.frame_acc == 0) {
                self.writeFrame();
                self.frame_acc = self.samples_per_frame;
            }
            const block = @min(@as(u32, @intCast(n - off)), self.frame_acc);
            audio.machineRenderYm(@intCast(off), block);
            self.frame_acc -= block;
            off += block;
        }
        audio.machineClamp(@intCast(n));
    }
};
