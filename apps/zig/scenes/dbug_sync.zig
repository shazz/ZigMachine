// --------------------------------------------------------------------------
// D-BUG screen — the music sync.
//
// The original does not animate the scroller with a sine. It watches the tune's
// playback position and moves to it (Codef `screen.js`: sndhMonitor,
// bouncingScroller, logoSpring):
//
//   until 12800 ms   the intro. The scroller sits still at its rest line and
//                    simply scrolls left; the logo does not move at all.
//   at 12800 ms      the scroller FALLS — the bounceStart curve, played once.
//   from 13600 ms    a beat every 1608 ms. Each beat restarts the bounce curve,
//                    which is STRETCHED to the beat interval, so the bump keeps
//                    time with the music however fast it is. Reaching the top of
//                    a bounce re-triggers the logo's spring.
//   at 89600 ms      stop beating: finish the bounce in progress, then ride the
//                    bounceStop curve back to rest and stay there.
//
// This is a pure state machine — milliseconds in, two numbers out — so it can be
// tested without a machine, a tune, or a screen. The curves themselves are
// generated from data.js by tools/dbug_curves.py, already converted into this
// screen's coordinates.
// --------------------------------------------------------------------------
const std = @import("std");

// The original's sync points, in milliseconds of tune. Not derived from
// anything: !Cube's arrangement, measured by Shiftcode.
pub const FALL_AT: u32 = 12800;
pub const FIRST_BEAT: u32 = 13600;
pub const STOP_BEAT_AT: u32 = 89600;
pub const BEAT_MS: u32 = 1608;

const RAW = @embedFile("../assets/screens/dbug/curves.dat");

fn count(i: usize) usize {
    return @as(usize, RAW[i * 2]) | (@as(usize, RAW[i * 2 + 1]) << 8);
}

const N_FALL = count(0);
const N_BOUNCE = count(1);
const N_STOP = count(2);
const N_SPRING = count(3);
const OFF_FALL = 8;
const OFF_BOUNCE = OFF_FALL + N_FALL;
const OFF_STOP = OFF_BOUNCE + N_BOUNCE;
const OFF_SPRING = OFF_STOP + N_STOP;

/// The scroller's top line through each move, and the logo's spring as a signed
/// delta from where it rests.
const FALL = RAW[OFF_FALL..OFF_BOUNCE];
const BOUNCE = RAW[OFF_BOUNCE..OFF_STOP];
const SETTLE = RAW[OFF_STOP..OFF_SPRING];
const SPRING = RAW[OFF_SPRING .. OFF_SPRING + N_SPRING];

/// Where the scroller sits when nothing is happening to it.
pub const REST: u16 = 44;
/// A bounce this high has hit the top, which is what kicks the logo.
const SPRING_TRIGGER: u16 = 84;
/// The original indexes its bounce curve with `length + 5`, so the last frames
/// of a beat run past the end of the table and the scroller waits at the bottom.
const BOUNCE_SPAN = N_BOUNCE + 5;

const Step = enum { intro, falling, beating, finishing, settling, done };

pub const Sync = struct {
    step: Step = .intro,
    next_beat: u32 = FIRST_BEAT,
    last_beat: u32 = 0,
    frame: usize = 0, // into the fall or settle curve
    spring: ?usize = null, // into the spring curve, null = logo at rest

    /// The scroller's top line this frame.
    y: u16 = REST,
    /// How far the logo is displaced from its rest position this frame.
    logo_dy: i16 = 0,

    /// Advance one frame, given how far into the tune we are. A song_ms of 0
    /// (nothing playing yet) simply holds the intro, which is what should
    /// happen while the viewer has not turned the sound on.
    pub fn update(self: *Sync, song_ms: u32) void {
        self.watchMusic(song_ms);
        self.moveScroller(song_ms);
        self.moveLogo();
    }

    // sndhMonitor: the beats, and the transitions between the four moves.
    fn watchMusic(self: *Sync, song_ms: u32) void {
        switch (self.step) {
            .intro => if (song_ms > FALL_AT) {
                self.step = .falling;
                self.next_beat = FIRST_BEAT;
                self.frame = 0;
                self.spring = 0; // the fall kicks the logo too
            },
            .falling, .beating => {
                if (song_ms > self.next_beat) {
                    self.next_beat += BEAT_MS;
                    self.last_beat = song_ms;
                    self.spring = 0;
                    self.step = .beating;
                }
                if (song_ms > STOP_BEAT_AT) self.step = .finishing;
            },
            else => {},
        }
    }

    // bouncingScroller.
    fn moveScroller(self: *Sync, song_ms: u32) void {
        switch (self.step) {
            .intro => self.y = REST,
            .falling => {
                self.y = FALL[@min(self.frame, N_FALL - 1)];
                if (self.frame + 1 < N_FALL) self.frame += 1;
            },
            // One bounce, stretched across the beat: the bump keeps time.
            .beating => self.y = self.bounceAt(song_ms -| self.last_beat),
            // Beating has stopped; ride out the bounce we are in and leave when
            // it next reaches the top.
            .finishing => {
                self.y = self.bounceAt((song_ms -| self.last_beat) % BEAT_MS);
                if (self.y == 0) {
                    self.step = .settling;
                    self.frame = 0;
                }
            },
            .settling => {
                self.y = SETTLE[@min(self.frame, N_STOP - 1)];
                self.frame += 1;
                if (self.frame >= N_STOP) self.step = .done;
            },
            .done => self.y = REST,
        }
        if (self.y >= SPRING_TRIGGER) self.spring = 0; // hit the bottom: kick the logo
    }

    fn bounceAt(self: *Sync, since_beat: u32) u16 {
        _ = self;
        const idx = since_beat * BOUNCE_SPAN / BEAT_MS;
        // Past the end of the table the original leaves the scroller sitting at
        // the bottom until the next beat comes.
        return if (idx < N_BOUNCE) BOUNCE[idx] else BOUNCE[0];
    }

    // logoSpring: one pass through the spring curve, then still again.
    fn moveLogo(self: *Sync) void {
        const i = self.spring orelse {
            self.logo_dy = 0;
            return;
        };
        self.logo_dy = @as(i8, @bitCast(SPRING[i]));
        self.spring = if (i + 1 < N_SPRING) i + 1 else null;
    }
};

test "the intro is still: the scroller rests and the logo does not move" {
    var s: Sync = .{};
    for (0..600) |_| s.update(0); // ten seconds with no tune playing at all
    try std.testing.expectEqual(REST, s.y);
    try std.testing.expectEqual(@as(i16, 0), s.logo_dy);

    for (0..60) |_| s.update(FALL_AT - 100); // still before the drop
    try std.testing.expectEqual(REST, s.y);
}

test "the scroller falls when the tune says so, and kicks the logo" {
    var s: Sync = .{};
    s.update(FALL_AT - 1);
    try std.testing.expectEqual(REST, s.y);

    s.update(FALL_AT + 1);
    try std.testing.expect(s.spring != null); // the logo is moving now
    var moved = false;
    for (0..40) |_| {
        s.update(FALL_AT + 10);
        if (s.y != REST) moved = true;
    }
    try std.testing.expect(moved);
}

test "the bump is stretched to the beat, so it keeps time" {
    var s: Sync = .{};
    s.update(FALL_AT + 1);
    s.update(FIRST_BEAT + 1); // first beat
    const at_beat = s.y;

    // A quarter of the way through a beat should be a quarter into the curve.
    s.update(FIRST_BEAT + 1 + BEAT_MS / 4);
    try std.testing.expect(s.y != at_beat);

    // ...and the frame right after the NEXT beat is back where a beat starts.
    s.update(FIRST_BEAT + BEAT_MS + 2);
    try std.testing.expectEqual(at_beat, s.y);
}

test "after the last beat the scroller settles back to rest and stays" {
    var s: Sync = .{};
    s.update(FALL_AT + 1);
    var t: u32 = FIRST_BEAT;
    while (t < STOP_BEAT_AT + 20 * BEAT_MS) : (t += 16) s.update(t);
    try std.testing.expectEqual(REST, s.y);
    try std.testing.expectEqual(@as(i16, 0), s.logo_dy);
}

test "the spring runs its course once and then holds still" {
    var s: Sync = .{};
    s.update(FALL_AT + 1); // kicks the spring
    var seen_nonzero = false;
    for (0..N_SPRING) |_| {
        s.update(FALL_AT + 2);
        if (s.logo_dy != 0) seen_nonzero = true;
    }
    try std.testing.expect(seen_nonzero);
}
