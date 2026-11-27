// --------------------------------------------------------------------------
// RACER: the cart's audio (M4): the music (music.zig) and the sound effects (sfx.zig) on the BARD
// queue's FM device (zg.bard.fm). Works on any Demo with `game`, `drive` and `audio` fields.
//   - The device is asked for (zg.caps .bard_fm) and opened at the first frame; it owns FM 5-6, PSG
//     tone 3 and the noise (SFX_DEFAULT) and its two FM voices get their patches. Without it (an older
//     system, a host with no queue) the music plays alone and stops by zg.stopSong.
//   - The music: SHIPPED's tunes (ours: M5 step 4's final tunes); with `-Dracer_music` the LOCAL tunes win (they use every
//     channel, so the effects start OFF there: key h takes the channels, muting those parts).
//   - Stamps: the cart's own sample clock, moved on by the real time between two frames (hostMicros), so
//     the queue's anchor keeps every write ~LEAD (70 ms) ahead whatever the cart's frame rate; if the
//     clock falls within MIN_AHEAD of the sound side's position (drift, a stall, no clock on a harness
//     machine) it jumps ahead to it. The device needs a write ~430 samples ahead to land on its stamp.
//   - The benchmark laps (b, x) are silent unless key j switches their audio on (music + effects), so
//     the earlier silent pins stay comparable; the audio never touches a pixel or a physics tick.
// Keys: z the music, h the effects, j the benchmark's audio.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const opts = @import("cart_opts");
const music = @import("music.zig");
const sfx = @import("sfx.zig");
const voices = @import("voices.zig");

pub const local: bool = opts.racer_music;
pub const LEAD: u32 = 3072; // the queue's lead, samples
pub const MIN_AHEAD: u32 = 2048; // the clock never stamps closer than this to the sound side's position
const MAX_STEP_US: u32 = 200_000; // a longer gap between frames (a stall, a pause) counts as this
const fm = zg.bard.fm;

pub const Audio = struct {
    player: music.Player = .{ .songs = if (local) &music.SONGS else &music.SHIPPED },
    fx: sfx.Sfx = .{},
    started: bool = false,
    device: bool = false, // the FM device is open
    effects: bool = !local,
    owning: bool = false,
    bench_audio: bool = false,
    t: u32 = 0, // the cart's sample clock: this frame's stamp
    now: *const fn () u32 = zeroClock, // microseconds (racer.zig gives hostMicros)
    last_us: u32 = 0,
    frac: u32 = 0, // samples x 10,000 not yet whole
    refused: u32 = 0, // writes the cart's ring or the device refused
    frames: u32 = 0,
    logged: [2]u32 = .{ 0xFFFF_FFFF, 0xFFFF_FFFF }, // the owning / refused last logged (racer,audio)

    fn start(self: *Audio) void {
        self.started = true;
        if (!zg.caps.has(.bard_fm) or !zg.bard.open(LEAD)) return;
        self.device = true;
        self.t = MIN_AHEAD;
        self.last_us = self.now();
        if (self.effects) self.take();
    }

    fn take(self: *Audio) void {
        self.owning = fm.own(self.t, fm.SFX_DEFAULT) and fm.patch(self.t, sfx.ENGINE, &voices.ENGINE) and
            fm.patch(self.t, sfx.IMPACT, &voices.IMPACT) and fm.freq(self.t, sfx.IMPACT, 2, 700);
        if (!self.owning) self.refused += 1;
    }

    /// Once a frame: the clock moved on by the real time since the last frame, never too close to the sound side.
    fn tick(self: *Audio) u32 {
        const us = self.now();
        const dt = @min(us -% self.last_us, MAX_STEP_US);
        self.last_us = us;
        const x = @as(u64, dt) * 441 + self.frac; // 44,100 samples a second = 441 per 10,000 us
        self.t +%= @intCast(x / 10_000);
        self.frac = @intCast(x % 10_000);
        const floor = zg.bard.position() +% MIN_AHEAD;
        if (zg.bard.anchored() and @as(i32, @bitCast(floor -% self.t)) > 0) self.t = floor;
        return self.t;
    }

    /// One frame: the music's wish and the effects' writes.
    pub fn step(self: *Audio, m: music.Ctx, s: sfx.Snap) void {
        if (!self.started) self.start();
        const t = if (self.device) self.tick() else 0;
        if (self.player.step(m)) |c| self.ask(c, t);
        self.frames +%= 1;
        self.retake();
        self.report();
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

    /// Bug pass (Matt 27 Nov, "no engine sound" on the board): the channels were asked for ONCE, at the first frame; one
    /// refusal there (a queue not ready yet) silenced the effects for the whole session. Ask again once a second.
    fn retake(self: *Audio) void {
        if (self.device and self.effects and !self.owning and self.frames % 60 == 0) self.take();
    }

    /// `racer,audio,<device>,<owning>,<refused>` on the console when the effects' state changes (the board's serial log
    /// says why it is silent).
    fn report(self: *Audio) void {
        const now = [2]u32{ @intFromBool(self.owning), self.refused };
        if (now[0] == self.logged[0] and (now[1] == self.logged[1] or self.frames % 60 != 0)) return;
        self.logged = now;
        zg.Console.log("racer,audio,{},{},{}", .{ @intFromBool(self.device), now[0], now[1] });
    }

    pub fn toggleMusic(self: *Audio) void {
        self.player.toggle();
    }

    /// Key h: the effects on (the channels taken, the voices patched) or off (silenced, given back to the tune).
    pub fn toggleEffects(self: *Audio) void {
        self.effects = !self.effects;
        if (!self.device) return;
        const t = self.t;
        if (self.effects) return self.take();
        var out: sfx.Out = .{};
        self.fx.quiet(&out);
        self.send(&out, t);
        if (!fm.own(t, 0)) self.refused += 1;
        self.owning = false;
    }
};

fn zeroClock() u32 {
    return 0;
}

/// The pause: what the effects sound is silenced (the music plays on); they start again with the race.
pub fn pause(self: anytype) void {
    const a = &self.audio;
    if (!a.owning) return;
    var out: sfx.Out = .{};
    a.fx.quiet(&out);
    a.send(&out, a.t);
}

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
