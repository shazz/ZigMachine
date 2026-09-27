// --------------------------------------------------------------------------
// A game's sound effects OVER a MOD (zg.sfxPlay / zg.sfxStop / zg.ymWrite;
// docs/MUSIC.md "Sound effects over a MOD").
//
// The audio module plays one song at a time, and a MOD holds all four Paula
// channels. So an effect BORROWS one: the song's quiet channel, the one with
// the fewest notes (mod_format.quietChannel), where the tune loses the least.
// It plays there at full volume (chipVolume(64), which keeps the song's 1/1.4
// headroom exact: still four channels at most) and at that channel's own pan.
// The song goes on reading the channel and writes nothing to it; when the
// effect is over the channel is the song's again (ModPlayer.reclaim):
//   - a one-shot, when its last sample has played (counted in output frames);
//   - a looped one (a gun burst), on sfxStop, or after LOOP_TIMEOUT if no
//     stop ever comes, so a lost stop cannot take the channel for good.
// One effect at a time, as on the ST's DMA chip: a new one cuts the old.
//
// The YM2149 is idle under a MOD, so a game's PSG note (an engine) is written
// to it register by register (ym) and mixed with the song from the first
// write (ModPlayer.mix_ym). Refused while an SNDH or a YM dump owns the chip.
// --------------------------------------------------------------------------
const audio = @import("audio_hw");
const ModPlayer = @import("mod.zig").ModPlayer;
const chipVolume = @import("mod.zig").chipVolume;
const pan = @import("mod.zig").pan;

/// The largest effect: 64 KiB is over five seconds at 12517 Hz.
pub const CAP: usize = 64 * 1024;
/// A looped effect gives its channel back after this long with no stop.
pub const LOOP_TIMEOUT: u32 = 4 * @as(u32, @intFromFloat(audio.SAMPLE_RATE));
pub const RATE_MIN: u32 = 1000;
pub const RATE_MAX: u32 = 50066;

/// The effect's PCM (signed 8-bit), written by the host (audioSfxBufPtr):
/// the top 64 KiB of song RAM. Not a static: 64 KiB of zeros in the data
/// segment (apps/zero_segments.mjs). A MOD reaching into it (over 960 KiB)
/// plays, but refuses effects.
pub const BUF_OFFSET: usize = audio.SONG_CAP - CAP;

pub fn buf() [*]u8 {
    return @ptrFromInt(audio.SONG_BASE + BUF_OFFSET);
}

pub const SfxVoice = struct {
    /// The Paula channel held, if any.
    ch: ?u8 = null,
    /// Output frames until the channel goes back.
    left: u32 = 0,
    looped: bool = false,
    /// The YM has been written since the last reset: mix it under the song.
    ym_live: bool = false,
    plays: u32 = 0,
    /// Effects and YM writes refused: no MOD playing, a bad length or rate,
    /// or the YM owned by another player. Never absorbed silently.
    refused: u32 = 0,

    /// Play the first `len` bytes of buf() at `rate` Hz over `mod`.
    pub fn play(self: *SfxVoice, mod: *ModPlayer, len: u32, rate: u32, loop: bool) bool {
        if (!mod.active or mod.data.len > BUF_OFFSET) return self.refuse();
        if (len == 0 or len > CAP or rate < RATE_MIN or rate > RATE_MAX) return self.refuse();
        const ch = self.ch orelse mod.lend();
        self.ch = ch;
        audio.machinePaulaTrigger(ch, audio.songAddr(BUF_OFFSET), len, 0, if (loop) len else 0, pan(ch));
        const step = @as(f32, @floatFromInt(rate)) / audio.SAMPLE_RATE * audio.FRAC_ONE;
        audio.machinePaulaSetStep(ch, @intFromFloat(step));
        audio.machinePaulaSetVolume(ch, chipVolume(64));
        self.looped = loop;
        self.left = if (loop) LOOP_TIMEOUT else frames(len, rate);
        self.plays +%= 1;
        return true;
    }

    /// Stop the effect (only a looped one when `loop_only`): the channel
    /// goes back to the song at once.
    pub fn stop(self: *SfxVoice, mod: *ModPlayer, loop_only: bool) void {
        if (self.ch == null or (loop_only and !self.looped)) return;
        self.release(mod);
    }

    /// `n` output frames have been rendered.
    pub fn advance(self: *SfxVoice, mod: *ModPlayer, n: u32) void {
        if (self.ch == null) return;
        if (self.left > n) {
            self.left -= n;
        } else self.release(mod);
    }

    /// The song was replaced or stopped: whatever channel was held is the
    /// new song's (its start retriggers every channel).
    pub fn songChanged(self: *SfxVoice) void {
        self.ch = null;
    }

    /// A YM register, for a PSG note under the song. `owned`: another player
    /// (an SNDH, a YM dump) drives the chip, so the write is refused.
    pub fn ym(self: *SfxVoice, reg: u32, val: u32, owned: bool) bool {
        if (owned or reg > 13) return self.refuse();
        if (!self.ym_live) silenceYm();
        self.ym_live = true;
        audio.machineYmWrite(reg, val & 0xFF);
        return true;
    }

    /// The chip was reset (a program ended) or handed to another player.
    pub fn reset(self: *SfxVoice) void {
        const refused = self.refused;
        self.* = .{};
        self.refused = refused;
    }

    fn release(self: *SfxVoice, mod: *ModPlayer) void {
        self.ch = null;
        mod.reclaim();
    }

    fn refuse(self: *SfxVoice) bool {
        self.refused +%= 1;
        return false;
    }
};

/// Output frames a one-shot of `len` bytes lasts at `rate` Hz, rounded up.
pub fn frames(len: u32, rate: u32) u32 {
    const sr: u64 = @intFromFloat(audio.SAMPLE_RATE);
    return @intCast((@as(u64, len) * sr + rate - 1) / rate);
}

/// Whatever an earlier player left in the tone and volume registers is not
/// the game's: mixer all off, volumes 0, before its first write.
fn silenceYm() void {
    audio.machineYmWrite(7, 0x3F);
    for (8..11) |r| audio.machineYmWrite(@intCast(r), 0);
}
