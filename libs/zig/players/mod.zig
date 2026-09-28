const audio = @import("audio_hw");
const fmt = @import("mod_format.zig");
const rows = @import("mod_rows.zig");

// --------------------------------------------------------------------------
// ProTracker .MOD player (4 channels, 31 samples: mod_format.zig refuses the
// rest) — an OPEN ZigOS player. It sequences a MOD image held in the shared
// song RAM (mod_rows.zig) and drives the SEALED Paula channels ONLY through
// the sdk/audio.zig chip API (machinePaula*). Its effects (mod_effects.zig)
// cover the common listenable set; the rest are ignored.
//
// A channel can be LENT to a game's sound effect (sfx_voice.zig): the song
// goes on reading it, row by row, but writes nothing to that Paula channel
// until it is reclaimed. Every chip write for a channel therefore goes
// through the setters below, which skip a lent one.
// --------------------------------------------------------------------------

const AMIGA_CLOCK: f32 = 7093789.2; // PAL Paula clock
const NUM_CH: usize = fmt.NUM_CH;
comptime {
    if (NUM_CH != audio.NUM_CHANNELS) @compileError("a MOD channel is a Paula channel");
}

// Headroom. Channels 0/3 pan to -0.6 and 1/2 to +0.6, so on each side two
// channels reach the bus at 0.5 and two at 0.2 (master 0.5): four full-scale
// samples sum to 1.4 and the bus clamp at 1.0 clipped them. An Amiga mixes its
// four channels in analogue and never clips, so the volume sent to the chip is
// scaled by 1/1.4: the worst case is exactly full scale.
const HEADROOM: f32 = 1.0 / 1.4;

pub fn chipVolume(vol: u8) f32 {
    return @as(f32, @floatFromInt(vol)) / 64.0 * HEADROOM;
}

/// The Amiga's hard stereo, softened: channels 0 and 3 left, 1 and 2 right.
pub fn pan(ch: usize) f32 {
    return if (ch == 0 or ch == 3) -0.6 else 0.6;
}

const ChanState = struct {
    sample: u8 = 0, // 1-based current sample (0 = none)
    period: u16 = 0, // current ProTracker period
    target_period: u16 = 0, // for tone portamento
    volume: u8 = 0, // 0..64
    porta_speed: u8 = 0,
    arp: u8 = 0, // arpeggio param (xy)
    eff: u8 = 0, // current row effect
    param: u8 = 0, // current row effect param
};

pub const ModPlayer = struct {
    data: []const u8 = &.{},
    hdr: fmt.Header = .{},
    /// The channel with the fewest notes: the one a sound effect borrows.
    quiet: u8 = 0,
    /// The channel lent to a sound effect, if one is.
    lent: ?u8 = null,
    /// Mix the YM2149 too (a game's PSG note under the song: sfx_voice.zig).
    mix_ym: bool = false,
    /// zg.requestModVolume: the song's channels scaled by this (0..1), never
    /// the lent one (its effect keeps chipVolume(64)). 1 on every load.
    gain: f32 = 1.0,
    active: bool = false,
    speed: u8 = 6, // ticks per row
    samples_per_tick: u32 = 882, // 44100 / (125*0.4)
    tick_acc: u32 = 0, // samples until next tick
    tick: u8 = 0, // current tick within row
    row: u8 = 0,
    order_pos: u8 = 0,
    break_row: i16 = -1, // pending pattern break target
    jump_pos: i16 = -1, // pending position jump target

    chan: [NUM_CH]ChanState = [_]ChanState{.{}} ** NUM_CH,

    /// Parse and check `data` (mod_format.zig). On an error nothing plays.
    pub fn load(self: *ModPlayer, data: []const u8) fmt.Error!void {
        self.* = .{};
        self.hdr = try fmt.parse(data);
        self.data = data;
        self.quiet = fmt.quietChannel(&self.hdr, data);
    }

    pub fn start(self: *ModPlayer) void {
        self.startAtBpm(125);
    }

    /// Start at `bpm` rather than ProTracker's 125: some replays default to
    /// another tempo (TRSI's Falcon replay, $7B = 123). An Fxx >= $20 in the
    /// song still overrides it, as on any ProTracker.
    pub fn startAtBpm(self: *ModPlayer, bpm: u8) void {
        self.active = true;
        self.speed = 6;
        self.setBpm(bpm);
        self.tick_acc = 0;
        self.tick = 0;
        self.row = 0;
        self.order_pos = 0;
        self.break_row = -1;
        self.jump_pos = -1;
        self.lent = null;
        for (&self.chan) |*c| c.* = .{};
    }

    pub fn stop(self: *ModPlayer) void {
        self.active = false;
    }

    pub fn setBpm(self: *ModPlayer, bpm: u16) void {
        self.samples_per_tick = @intFromFloat(audio.SAMPLE_RATE / (@as(f32, @floatFromInt(bpm)) * 0.4));
    }

    pub fn periodToStep(period: u16) u32 {
        if (period == 0) return 0;
        const rate = AMIGA_CLOCK / (@as(f32, @floatFromInt(period)) * 2.0);
        return @intFromFloat(rate / audio.SAMPLE_RATE * audio.FRAC_ONE);
    }

    // --- the chip, for the song's own channels only ----------------------
    fn owns(self: *const ModPlayer, ch: usize) bool {
        const l = self.lent orelse return true;
        return l != ch;
    }
    pub fn setStep(self: *ModPlayer, ch: usize, step: u32) void {
        if (self.owns(ch)) audio.machinePaulaSetStep(@intCast(ch), step);
    }
    pub fn setVolume(self: *ModPlayer, ch: usize, vol: u8) void {
        if (self.owns(ch)) audio.machinePaulaSetVolume(@intCast(ch), chipVolume(vol) * self.gain);
    }
    pub fn setPos(self: *ModPlayer, ch: usize, pos: u32) void {
        if (self.owns(ch)) audio.machinePaulaSetPos(@intCast(ch), pos);
    }

    /// Scale the song's channels by `g`, 0..1 (else refused: false), at once.
    /// Below 1 the worst case stays under full scale, as HEADROOM has it.
    pub fn setGain(self: *ModPlayer, g: f32) bool {
        if (!(g >= 0.0 and g <= 1.0)) return false; // NaN fails both
        self.gain = g;
        for (0..NUM_CH) |ch| self.setVolume(ch, self.chan[ch].volume);
        return true;
    }

    /// Lend the quiet channel to a sound effect. The song goes on tracking
    /// it and writes nothing to it until reclaim().
    pub fn lend(self: *ModPlayer) u8 {
        self.lent = self.quiet;
        return self.quiet;
    }

    /// The effect is over: the channel is the song's again. A looped sample
    /// the song holds there (a pad) sounds again from its loop; anything
    /// else waits for the channel's next note.
    pub fn reclaim(self: *ModPlayer) void {
        const ch = self.lent orelse return;
        self.lent = null;
        const cs = &self.chan[ch];
        const s = self.hdr.samples[cs.sample];
        if (self.active and cs.sample != 0 and s.loop_len > 2 and cs.period != 0) {
            self.trigger(ch);
            self.setPos(ch, s.loop_start);
            self.applyToEngine(ch);
        } else audio.machinePaulaSetActive(ch, 0);
    }

    // Render `frames` stereo samples, the sequencer ticked at sample-accurate
    // boundaries; the SEALED chip mixes the channels this player sets up.
    pub fn renderStereo(self: *ModPlayer, frames: usize) void {
        const n = @min(frames, audio.MAX_FRAMES);
        audio.machineClear(@intCast(n));
        var off: usize = 0;
        while (off < n) {
            if (self.tick_acc == 0) {
                rows.tick(self);
                self.tick_acc = self.samples_per_tick;
            }
            const block = @min(@as(u32, @intCast(n - off)), self.tick_acc);
            if (self.mix_ym) audio.machineRenderYm(@intCast(off), block);
            audio.machineMixPaula(@intCast(off), block);
            self.tick_acc -= block;
            off += block;
        }
        audio.machineClamp(@intCast(n));
    }

    pub fn trigger(self: *ModPlayer, ch: usize) void {
        if (!self.owns(ch)) return;
        const cs = &self.chan[ch];
        const s = self.hdr.samples[cs.sample];
        if (cs.sample == 0 or s.len == 0 or s.start + s.len > self.data.len) {
            audio.machinePaulaSetActive(@intCast(ch), 0);
            return;
        }
        const loop_len: u32 = if (s.loop_len > 2) s.loop_len else 0;
        audio.machinePaulaTrigger(@intCast(ch), audio.songAddr(s.start), s.len, s.loop_start, loop_len, pan(ch));
    }

    pub fn applyToEngine(self: *ModPlayer, ch: usize) void {
        self.setVolume(ch, self.chan[ch].volume);
        self.setStep(ch, periodToStep(self.chan[ch].period));
    }
};
