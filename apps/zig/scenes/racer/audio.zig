// --------------------------------------------------------------------------
// RACER: the cart's audio (M4): the music (music.zig) and the sound effects (sfx.zig) on the BARD
// queue's FM device (zg.bard.fm). Works on any Demo with `game`, `drive` and `audio` fields.
//   - The device is asked for (zg.caps .bard_fm) and opened at the first frame; it owns FM 5-6, PSG
//     tone 3 and the noise (SFX_DEFAULT) and its two FM voices get their patches. Without it (an older
//     system, a host with no queue) the music plays alone and stops by zg.stopSong.
//   - The music: SHIPPED's placeholder tunes; with `-Dracer_music` the LOCAL tunes win (they use every
//     channel, so the effects start OFF there: key h takes the channels, muting those parts).
//   - Stamps: each frame's writes at the sound side's position + AHEAD (never going back), so they
//     arrive ~35 ms ahead whatever the cart's frame rate, past the device's ~430-sample read-ahead.
//   - The benchmark laps (b, x) are silent unless key j switches their audio on (music + effects), so
//     the earlier silent pins stay comparable; the audio never touches a pixel or a physics tick.
// Keys: z the music, h the effects, j the benchmark's audio.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const opts = @import("cart_opts");
const music = @import("music.zig");
const sfx = @import("sfx.zig");
const fsm = @import("fsm.zig");

pub const local: bool = opts.racer_music;
pub const LEAD: u32 = 3072; // the queue's lead, samples
pub const AHEAD: u32 = 1536; // a frame's writes are stamped this far past the sound side's position
const fm = zg.bard.fm;

pub const Audio = struct {
    player: music.Player = .{ .songs = if (local) &music.SONGS else &music.SHIPPED },
    fx: sfx.Sfx = .{},
    started: bool = false,
    device: bool = false, // the FM device is open
    effects: bool = !local,
    owning: bool = false,
    bench_audio: bool = false,
    t: u32 = 0,
    refused: u32 = 0, // writes the cart's ring or the device refused

    fn start(self: *Audio) void {
        self.started = true;
        if (!zg.caps.has(.bard_fm) or !zg.bard.open(LEAD)) return;
        self.device = true;
        self.t = AHEAD;
        if (self.effects) self.take();
    }

    fn take(self: *Audio) void {
        self.owning = fm.own(self.t, fm.SFX_DEFAULT) and fm.patch(self.t, sfx.ENGINE, &ENGINE_PATCH) and
            fm.patch(self.t, sfx.IMPACT, &IMPACT_PATCH) and fm.freq(self.t, sfx.IMPACT, 2, 700);
        if (!self.owning) self.refused += 1;
    }

    fn stamp(self: *Audio) u32 {
        const at = zg.bard.position() +% AHEAD;
        if (@as(i32, @bitCast(at -% self.t)) > 0) self.t = at;
        return self.t;
    }

    /// One frame: the music's wish and the effects' writes.
    pub fn step(self: *Audio, m: music.Ctx, s: sfx.Snap) void {
        if (!self.started) self.start();
        const t = if (self.device) self.stamp() else 0;
        if (self.player.step(m)) |c| self.ask(c, t);
        if (!self.owning or !zg.bard.anchored()) return; // nothing taken yet (the page before its sound is on): no effect state to lose
        var out: sfx.Out = .{};
        self.fx.step(s, &out);
        self.send(&out, t);
    }

    fn ask(self: *Audio, c: music.Cue, t: u32) void {
        if (c != .silent) return zg.requestSong(self.player.name(c));
        if (self.device) {
            if (!fm.tuneStop(t)) self.refused += 1;
        } else zg.stopSong();
    }

    fn send(self: *Audio, out: *const sfx.Out, t: u32) void {
        for (out.items()) |w| {
            const ok = switch (w.kind) {
                .ym0 => fm.ym(t, 0, w.reg, w.val),
                .ym1 => fm.ym(t, 1, w.reg, w.val),
                .psg => fm.psg(t, w.val),
            };
            if (!ok) self.refused += 1;
        }
        self.refused += out.dropped;
    }

    pub fn toggleMusic(self: *Audio) void {
        self.player.toggle();
    }

    /// Key h: the effects on (the channels taken, the voices patched) or off (silenced, given back to the tune).
    pub fn toggleEffects(self: *Audio) void {
        self.effects = !self.effects;
        if (!self.device) return;
        const t = self.stamp();
        if (self.effects) return self.take();
        var out: sfx.Out = .{};
        self.fx.quiet(&out);
        self.send(&out, t);
        if (!fm.own(t, 0)) self.refused += 1;
        self.owning = false;
    }
};

/// The engine: algorithm 4 (two pairs), a growl of feedback, held while keyed.
pub const ENGINE_PATCH = fm.Patch{ .fb_alg = 5 << 3 | 4, .ops = .{
    .{ .dt_mul = 0x01, .tl = 30, .ks_ar = 31, .sl_rr = 0x0F },
    .{ .dt_mul = 0x01, .tl = 22, .ks_ar = 31, .sl_rr = 0x0F },
    .{ .dt_mul = 0x02, .tl = 28, .ks_ar = 31, .sl_rr = 0x0F },
    .{ .dt_mul = 0x01, .tl = 24, .ks_ar = 31, .sl_rr = 0x0F },
} };
/// The impact: a serial chain with full feedback, low, decaying in ~0.2 s.
pub const IMPACT_PATCH = fm.Patch{ .fb_alg = 7 << 3 | 0, .ops = .{
    .{ .dt_mul = 0x03, .tl = 20, .ks_ar = 31, .am_dr = 14, .sl_rr = 0xFF },
    .{ .dt_mul = 0x01, .tl = 28, .ks_ar = 31, .am_dr = 12, .sl_rr = 0xFF },
    .{ .dt_mul = 0x05, .tl = 30, .ks_ar = 31, .am_dr = 12, .sl_rr = 0xFF },
    .{ .dt_mul = 0x01, .tl = 6, .ks_ar = 31, .am_dr = 16, .sl_rr = 0xFF },
} };

/// The music's and the effects' view of a Demo, once a frame.
pub fn frame(self: anytype) void {
    const g = &self.game;
    const bench = g.mode == .bench or self.drive.mode == .bench;
    const quiet = bench and !self.audio.bench_audio;
    const m = music.Ctx{
        .bench = quiet,
        .driving = self.drive.mode == .drive,
        .racing = g.mode != .off,
        .state = g.s.fsm.state,
        .ticks = g.s.fsm.ticks,
        .outcome = g.s.outcome,
    };
    self.audio.step(m, if (quiet) .{} else snap(self));
}

fn snap(self: anytype) sfx.Snap {
    const g = &self.game;
    if (g.mode != .off) {
        const s = &g.s;
        const c = &s.race.cars[0];
        const st = s.fsm.state;
        return .{
            .racing = st == .countdown or st == .race or st == .finish,
            .state = st,
            .ticks = s.fsm.ticks,
            .rpm = c.rpm,
            .slide = c.front_slide or c.rear_slide,
            .knocks = c.hits +% s.race.contacts,
            .gates = s.rules.nlaps * @as(u32, @intCast(s.rules.checkpoints.len)) + s.rules.checkpoint,
            .laps = s.rules.nlaps,
            .outcome = s.outcome,
        };
    }
    if (self.drive.mode == .off) return .{};
    const c = &self.drive.car;
    return .{ .racing = true, .state = .race, .rpm = c.rpm, .slide = c.front_slide or c.rear_slide, .knocks = c.hits };
}

/// The cart's audio keys; false: not one of them.
pub fn key(self: anytype, cp: u32) bool {
    switch (cp) {
        'z' => self.audio.toggleMusic(),
        'h' => self.audio.toggleEffects(),
        'j' => self.audio.bench_audio = !self.audio.bench_audio,
        else => return false,
    }
    return true;
}
