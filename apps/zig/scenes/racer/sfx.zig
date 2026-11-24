// --------------------------------------------------------------------------
// RACER: the sound effects (M4), as register writes for the BARD queue's FM device (zg.bard.fm) on the
// channels the cart owns (FM 5-6, PSG tone 3, the noise; the tunes play FM 1-4 + PSG 1-2):
//   engine    FM 6, keyed while the player's car runs; its pitch follows the rpm (a write pair when it moves)
//   impact    FM 5, a short percussive note on a wall hit or a contact with another car
//   skid      the noise, while a tyre slides
//   beeps     PSG tone 3: the countdown (3 low, go high), the checkpoint chime, the lap and finish jingles,
//             the time-out phrase; a new phrase replaces the one playing
// `step` is one frame: it compares the race's state with the last frame's and says what changed, a few
// writes at most (none on a quiet frame). Integer only. No ZigOS import (audio.zig sends the writes).
// --------------------------------------------------------------------------
const fsm = @import("fsm.zig");
const rules = @import("rules.zig");

pub const ENGINE: u3 = 5; // FM 6
pub const IMPACT: u3 = 4; // FM 5
pub const BEEP: u2 = 2; // PSG tone 3
pub const MAX_RPM: i32 = 39322; // car.zig max_rpm, lit(0.6)
pub const IDLE_FNUM: u32 = 300; // block 3: ~61 Hz
pub const TOP_FNUM: u32 = 1200; // ~244 Hz at max rpm
const PITCH_STEP: u32 = 6; // a smaller move is not written
const BEEP_ATT: u4 = 3;
/// Frames an impact stays keyed: its sound has decayed by then, and a tune load (which puts the cart's
/// channels back as they were, keys included) must not replay it.
pub const IMPACT_FRAMES: u8 = 12;
const SKID_ATT: u4 = 5;

/// What the effects look at, once a frame.
pub const Snap = struct {
    racing: bool = false, // the engine runs (countdown, race, finish; free drive)
    state: fsm.State = .grid,
    ticks: u32 = 0, // in the state
    rpm: i32 = 0,
    slide: bool = false,
    knocks: u32 = 0, // wall hits + car contacts, ever growing
    gates: u32 = 0, // checkpoints passed (laps x checkpoints + checkpoint)
    laps: u32 = 0,
    outcome: rules.Result = .none,
};

pub const Kind = enum(u8) { ym0, ym1, psg };
pub const Write = struct { kind: Kind, reg: u8 = 0, val: u8 };

/// A frame's writes; more than CAP are dropped (counted): a frame never floods the queue.
pub const Out = struct {
    pub const CAP = 24;
    buf: [CAP]Write = undefined,
    n: u32 = 0,
    dropped: u32 = 0,

    fn put(self: *Out, w: Write) void {
        if (self.n == CAP) {
            self.dropped += 1;
            return;
        }
        self.buf[self.n] = w;
        self.n += 1;
    }
    pub fn items(self: *const Out) []const Write {
        return self.buf[0..self.n];
    }
};

/// A PSG note: a 10-bit period (3,579,545 / 32 / period Hz) for `frames` frames; period 0 is a rest.
pub const Note = struct { period: u10, frames: u8 };
pub const COUNT = [_]Note{.{ .period = 254, .frames = 10 }}; // A4
pub const GO = [_]Note{.{ .period = 127, .frames = 24 }}; // A5
pub const CHIME = [_]Note{ .{ .period = 170, .frames = 6 }, .{ .period = 113, .frames = 14 } }; // E5 B5
pub const LAP = [_]Note{ .{ .period = 214, .frames = 6 }, .{ .period = 170, .frames = 6 }, .{ .period = 143, .frames = 6 }, .{ .period = 107, .frames = 18 } }; // C5 E5 G5 C6
pub const WIN = [_]Note{ .{ .period = 143, .frames = 8 }, .{ .period = 107, .frames = 8 }, .{ .period = 85, .frames = 8 }, .{ .period = 0, .frames = 4 }, .{ .period = 85, .frames = 8 }, .{ .period = 71, .frames = 40 } };
pub const LOSE = [_]Note{ .{ .period = 286, .frames = 14 }, .{ .period = 340, .frames = 14 }, .{ .period = 428, .frames = 40 } }; // G4 E4 C4

pub fn engineFnum(rpm: i32) u32 {
    const r: u32 = @intCast(@max(0, @min(rpm, MAX_RPM)));
    return IDLE_FNUM + r * (TOP_FNUM - IDLE_FNUM) / @as(u32, MAX_RPM);
}

pub const Sfx = struct {
    prev: Snap = .{},
    engine: bool = false,
    fnum: u32 = 0,
    skid: bool = false,
    impact_left: u8 = 0,
    phrase: []const Note = &.{},
    at: u32 = 0, // the note playing
    left: u32 = 0, // its frames left

    pub fn step(self: *Sfx, s: Snap, out: *Out) void {
        self.engineStep(s, out);
        self.skidStep(s, out);
        self.impactStep(s, out);
        if (cue(self.prev, s)) |p| self.play(p, out) else self.advance(out);
        self.prev = s;
    }

    /// Everything the cart owns silent (a mode change, the effects switched off).
    pub fn quiet(self: *Sfx, out: *Out) void {
        if (self.engine) key(out, ENGINE, 0);
        if (self.impact_left > 0) key(out, IMPACT, 0);
        if (self.skid) out.put(.{ .kind = .psg, .val = 0xF0 | 15 });
        if (self.left > 0) out.put(.{ .kind = .psg, .val = 0x90 | @as(u8, BEEP) << 5 | 15 });
        self.* = .{};
    }

    fn engineStep(self: *Sfx, s: Snap, out: *Out) void {
        if (s.racing != self.engine) {
            if (s.racing) self.pitch(engineFnum(s.rpm), out);
            key(out, ENGINE, if (s.racing) 0xF else 0);
            self.engine = s.racing;
        }
        if (!s.racing) return;
        const f = engineFnum(s.rpm);
        const d = if (f > self.fnum) f - self.fnum else self.fnum - f;
        if (d >= PITCH_STEP) self.pitch(f, out);
    }

    fn pitch(self: *Sfx, f: u32, out: *Out) void {
        self.fnum = f;
        out.put(.{ .kind = .ym1, .reg = 0xA6, .val = 3 << 3 | @as(u8, @intCast(f >> 8)) });
        out.put(.{ .kind = .ym1, .reg = 0xA2, .val = @truncate(f) });
    }

    fn impactStep(self: *Sfx, s: Snap, out: *Out) void {
        if (s.knocks > self.prev.knocks) {
            impact(out);
            self.impact_left = IMPACT_FRAMES;
        } else if (self.impact_left > 0) {
            self.impact_left -= 1;
            if (self.impact_left == 0) key(out, IMPACT, 0);
        }
    }

    fn skidStep(self: *Sfx, s: Snap, out: *Out) void {
        const on = s.slide and s.racing and s.state == .race;
        if (on == self.skid) return;
        if (on) out.put(.{ .kind = .psg, .val = 0xE0 | 5 }); // white noise, clock / 1024
        out.put(.{ .kind = .psg, .val = 0xF0 | @as(u8, if (on) SKID_ATT else 15) });
        self.skid = on;
    }

    fn play(self: *Sfx, p: []const Note, out: *Out) void {
        self.phrase = p;
        self.at = 0;
        self.note(out);
    }

    fn note(self: *Sfx, out: *Out) void {
        const n = self.phrase[self.at];
        self.left = n.frames;
        const c: u8 = @as(u8, BEEP) << 5;
        if (n.period == 0) {
            out.put(.{ .kind = .psg, .val = 0x90 | c | 15 });
            return;
        }
        out.put(.{ .kind = .psg, .val = 0x80 | c | @as(u8, @truncate(n.period & 15)) });
        out.put(.{ .kind = .psg, .val = @intCast(n.period >> 4) });
        out.put(.{ .kind = .psg, .val = 0x90 | c | BEEP_ATT });
    }

    fn advance(self: *Sfx, out: *Out) void {
        if (self.left == 0) return;
        self.left -= 1;
        if (self.left > 0) return;
        self.at += 1;
        if (self.at < self.phrase.len) return self.note(out);
        out.put(.{ .kind = .psg, .val = 0x90 | @as(u8, BEEP) << 5 | 15 });
    }
};

fn key(out: *Out, ch: u3, slots: u8) void {
    const code: u8 = if (ch < 3) ch else @as(u8, ch) + 1;
    out.put(.{ .kind = .ym0, .reg = 0x28, .val = slots << 4 | code });
}

fn impact(out: *Out) void {
    key(out, IMPACT, 0);
    key(out, IMPACT, 0xF);
}

/// The phrase a change of the race's state starts, or null.
pub fn cue(a: Snap, b: Snap) ?[]const Note {
    if (b.outcome != a.outcome) return switch (b.outcome) {
        .win => &WIN,
        .timeout => &LOSE,
        else => null,
    };
    if (b.state == .countdown and (a.state != .countdown or crossed(a.ticks, b.ticks, 30) or crossed(a.ticks, b.ticks, 60))) return &COUNT;
    if (b.state == .race and a.state == .countdown) return &GO;
    if (b.laps > a.laps) return &LAP;
    if (b.gates > a.gates) return &CHIME;
    return null;
}

fn crossed(a: u32, b: u32, at: u32) bool {
    return a < at and b >= at;
}
