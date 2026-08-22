const std = @import("std");
const engine_mod = @import("engine.zig");
const Engine = engine_mod.Engine;
const Channel = engine_mod.Channel;

// --------------------------------------------------------------------------
// ProTracker .MOD player (4 channels, 31 samples, "M.K.").
//
// Parses a MOD image held in a caller-owned byte buffer and sequences it on the
// audio thread, driving the engine's Paula channels. Effects implemented cover
// the common listenable set; ornaments not yet handled are simply ignored.
// --------------------------------------------------------------------------

const AMIGA_CLOCK: f32 = 7093789.2; // PAL Paula clock
const FRAC_BITS: u6 = 16;
const FRAC_ONE: f32 = 65536.0;
const NUM_CH: usize = engine_mod.NUM_CHANNELS;

const SampleHdr = struct {
    start: u32 = 0, // byte offset into the MOD image of the PCM data
    len: u32 = 0, // in bytes
    loop_start: u32 = 0, // in bytes
    loop_len: u32 = 0, // in bytes
    volume: u8 = 0, // 0..64
    finetune: i8 = 0,
};

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
    samples: [32]SampleHdr = [_]SampleHdr{.{}} ** 32,
    song_len: u8 = 0,
    order: [128]u8 = [_]u8{0} ** 128,
    pattern_data: u32 = 0, // byte offset where patterns start
    num_patterns: u16 = 0,

    // sequencer state
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

    fn rd16(self: *ModPlayer, off: usize) u16 {
        return (@as(u16, self.data[off]) << 8) | self.data[off + 1];
    }

    pub fn load(self: *ModPlayer, data: []const u8) bool {
        self.* = .{};
        self.data = data;
        if (data.len < 1084) return false;

        // 31 sample headers at offset 20, 30 bytes each
        var pcm_total: u32 = 0;
        var i: usize = 1;
        while (i <= 31) : (i += 1) {
            const base = 20 + (i - 1) * 30;
            var s = &self.samples[i];
            s.len = @as(u32, self.rd16(base + 22)) * 2;
            const ft: u4 = @truncate(self.data[base + 24] & 0x0F);
            s.finetune = @as(i4, @bitCast(ft)); // 4-bit signed: 0..7 = 0..7, 8..15 = -8..-1
            s.volume = self.data[base + 25];
            s.loop_start = @as(u32, self.rd16(base + 26)) * 2;
            s.loop_len = @as(u32, self.rd16(base + 28)) * 2;
            pcm_total += s.len;
        }

        self.song_len = self.data[950];
        var max_pat: u16 = 0;
        i = 0;
        while (i < 128) : (i += 1) {
            self.order[i] = self.data[952 + i];
            if (self.order[i] > max_pat) max_pat = self.order[i];
        }
        self.num_patterns = max_pat + 1;
        self.pattern_data = 1084;

        // PCM data follows the patterns; fill in per-sample start offsets
        var pcm_off: u32 = self.pattern_data + @as(u32, self.num_patterns) * 1024;
        i = 1;
        while (i <= 31) : (i += 1) {
            self.samples[i].start = pcm_off;
            pcm_off += self.samples[i].len;
        }
        return true;
    }

    pub fn start(self: *ModPlayer) void {
        self.active = true;
        self.speed = 6;
        self.setBpm(125);
        self.tick_acc = 0;
        self.tick = 0;
        self.row = 0;
        self.order_pos = 0;
        self.break_row = -1;
        self.jump_pos = -1;
        for (&self.chan) |*c| c.* = .{};
    }

    pub fn stop(self: *ModPlayer) void {
        self.active = false;
    }

    fn setBpm(self: *ModPlayer, bpm: u16) void {
        // ticks/sec = bpm * 0.4  ->  samples/tick = SR / (bpm*0.4)
        const sr = engine_mod.SAMPLE_RATE;
        self.samples_per_tick = @intFromFloat(sr / (@as(f32, @floatFromInt(bpm)) * 0.4));
    }

    fn periodToStep(period: u16) u32 {
        if (period == 0) return 0;
        const rate = AMIGA_CLOCK / (@as(f32, @floatFromInt(period)) * 2.0);
        return @intFromFloat(rate / engine_mod.SAMPLE_RATE * FRAC_ONE);
    }

    // Render `frames` stereo samples: drive Paula channels, ticking the
    // sequencer at sample-accurate tick boundaries. The player owns the
    // scheduling; the engine just mixes the channels it sets up.
    pub fn renderStereo(self: *ModPlayer, eng: *Engine, frames: usize) void {
        const n = @min(frames, engine_mod.MAX_FRAMES);
        eng.clearBus(n);
        var off: usize = 0;
        while (off < n) {
            if (self.tick_acc == 0) {
                self.doTick(eng);
                self.tick_acc = self.samples_per_tick;
            }
            const block = @min(@as(u32, @intCast(n - off)), self.tick_acc);
            eng.mixChannels(eng.left[off .. off + block], eng.right[off .. off + block]);
            self.tick_acc -= block;
            off += block;
        }
        eng.clampBus(n);
    }

    // Called when a tick boundary is reached.
    pub fn doTick(self: *ModPlayer, eng: *Engine) void {
        if (!self.active) return;
        if (self.tick == 0) {
            self.processRow(eng);
        } else {
            self.processEffects(eng);
        }
        self.tick += 1;
        if (self.tick >= self.speed) {
            self.tick = 0;
            self.advanceRow();
        }
    }

    fn advanceRow(self: *ModPlayer) void {
        if (self.jump_pos >= 0) {
            self.order_pos = @intCast(self.jump_pos);
            self.row = if (self.break_row >= 0) @intCast(self.break_row) else 0;
            self.jump_pos = -1;
            self.break_row = -1;
            return;
        }
        if (self.break_row >= 0) {
            self.row = @intCast(self.break_row);
            self.break_row = -1;
            self.order_pos +%= 1;
            if (self.order_pos >= self.song_len) self.order_pos = 0;
            return;
        }
        self.row += 1;
        if (self.row >= 64) {
            self.row = 0;
            self.order_pos +%= 1;
            if (self.order_pos >= self.song_len) self.order_pos = 0;
        }
    }

    fn trigger(self: *ModPlayer, eng: *Engine, ch: usize) void {
        const cs = &self.chan[ch];
        var c = &eng.channels[ch];
        const s = self.samples[cs.sample];
        if (cs.sample == 0 or s.len == 0 or s.start + s.len > self.data.len) {
            c.active = false;
            return;
        }
        c.data = std.mem.bytesAsSlice(i8, self.data[s.start .. s.start + s.len]);
        c.pos = 0;
        c.loop_start = s.loop_start;
        c.loop_len = if (s.loop_len > 2) s.loop_len else 0;
        c.pan = if (ch == 0 or ch == 3) -0.6 else 0.6;
        c.active = true;
    }

    fn applyToEngine(self: *ModPlayer, eng: *Engine, ch: usize) void {
        const cs = &self.chan[ch];
        var c = &eng.channels[ch];
        c.volume = @as(f32, @floatFromInt(cs.volume)) / 64.0;
        c.step = periodToStep(cs.period);
    }

    fn cellByte(self: *ModPlayer, ch: usize, n: usize) u8 {
        const pattern = self.order[self.order_pos];
        const o = self.pattern_data + @as(u32, pattern) * 1024 + @as(u32, self.row) * 16 + @as(u32, @intCast(ch)) * 4 + n;
        return if (o < self.data.len) self.data[o] else 0;
    }

    fn processRow(self: *ModPlayer, eng: *Engine) void {
        var ch: usize = 0;
        while (ch < NUM_CH) : (ch += 1) {
            const b0 = self.cellByte(ch, 0);
            const b1 = self.cellByte(ch, 1);
            const b2 = self.cellByte(ch, 2);
            const b3 = self.cellByte(ch, 3);
            const period: u16 = (@as(u16, b0 & 0x0F) << 8) | b1;
            const sample: u8 = (b0 & 0xF0) | (b2 >> 4);
            var cs = &self.chan[ch];
            cs.eff = b2 & 0x0F;
            cs.param = b3;

            if (sample != 0 and sample <= 31) {
                cs.sample = sample;
                cs.volume = self.samples[sample].volume;
            }
            if (period != 0) {
                if (cs.eff == 3 or cs.eff == 5) {
                    cs.target_period = period;
                    if (cs.eff == 3 and cs.param != 0) cs.porta_speed = cs.param;
                } else {
                    cs.period = period;
                    self.trigger(eng, ch);
                }
            }
            self.rowEffect(eng, ch);
            self.applyToEngine(eng, ch);
        }
    }

    fn rowEffect(self: *ModPlayer, eng: *Engine, ch: usize) void {
        const cs = &self.chan[ch];
        switch (cs.eff) {
            0x0 => cs.arp = cs.param,
            0xC => cs.volume = @min(cs.param, 64),
            0xF => if (cs.param < 0x20) {
                if (cs.param > 0) self.speed = cs.param;
            } else self.setBpm(cs.param),
            0xB => self.jump_pos = cs.param,
            0xD => self.break_row = @intCast((cs.param >> 4) * 10 + (cs.param & 0x0F)),
            0x9 => eng.channels[ch].pos = @as(u64, @as(u32, cs.param) * 256) << FRAC_BITS,
            else => {},
        }
    }

    fn processEffects(self: *ModPlayer, eng: *Engine) void {
        var ch: usize = 0;
        while (ch < NUM_CH) : (ch += 1) {
            var cs = &self.chan[ch];
            var c = &eng.channels[ch];
            switch (cs.eff) {
                0x0 => if (cs.arp != 0) {
                    const semi: u8 = switch (self.tick % 3) {
                        0 => 0,
                        1 => cs.arp >> 4,
                        else => cs.arp & 0x0F,
                    };
                    const mul = std.math.pow(f32, 2.0, @as(f32, @floatFromInt(semi)) / 12.0);
                    c.step = @intFromFloat(@as(f32, @floatFromInt(periodToStep(cs.period))) * mul);
                },
                0x1 => {
                    cs.period = if (cs.period > cs.param + 113) cs.period - cs.param else 113;
                    c.step = periodToStep(cs.period);
                },
                0x2 => {
                    cs.period = @min(856, cs.period + @as(u16, cs.param));
                    c.step = periodToStep(cs.period);
                },
                0x3 => self.tonePorta(eng, ch),
                0xA => {
                    const up = cs.param >> 4;
                    const down = cs.param & 0x0F;
                    const v: i16 = @as(i16, cs.volume) + up - down;
                    cs.volume = @intCast(std.math.clamp(v, 0, 64));
                    c.volume = @as(f32, @floatFromInt(cs.volume)) / 64.0;
                },
                else => {},
            }
        }
    }

    fn tonePorta(self: *ModPlayer, eng: *Engine, ch: usize) void {
        var cs = &self.chan[ch];
        if (cs.target_period == 0 or cs.porta_speed == 0) return;
        if (cs.period < cs.target_period) {
            cs.period = @min(cs.target_period, cs.period + cs.porta_speed);
        } else if (cs.period > cs.target_period) {
            cs.period = if (cs.period > cs.target_period + cs.porta_speed) cs.period - cs.porta_speed else cs.target_period;
        }
        eng.channels[ch].step = periodToStep(cs.period);
    }
};
