// --------------------------------------------------------------------------
// The ribbon clock -- internal/source/clock.go of go-larcociel5, transcribed
// statement for statement.
//
// The trail is SIGNED 16-BIT with the original's WRAPPING arithmetic (Go's
// `int16 +=`), a pause of 62 ticks at reset and 61 more every 320 ticks, a
// 5-tick velocity integrator, and a 50-entry X history (one ribbon row each).
// The native checkpoint in tools/larcociel5/native-ribbon-149.json pins step
// 149; the headless harness asserts it against these very words.
// --------------------------------------------------------------------------
const std = @import("std");

pub const Clock = struct {
    tick: u32 = 0,
    counter: i32 = 0,
    hold: i32 = 62,
    x: i16 = 0,
    y: i16 = 0,
    vx: i16 = 0,
    vy: i16 = 0,
    ax: i16 = 0,
    ay: i16 = 0,
    history: [50]i16 = [_]i16{0} ** 50,

    fn beWord(b: []const u8, at: usize) i16 {
        return @bitCast(@as(u16, b[at]) << 8 | b[at + 1]);
    }

    /// motion 12 bytes (VX, AX, X, VY, AY, Y big-endian int16), history 100.
    pub fn init(motion: []const u8, history: []const u8) Clock {
        var c = Clock{};
        c.vx = beWord(motion, 0);
        c.ax = beWord(motion, 2);
        c.x = beWord(motion, 4);
        c.vy = beWord(motion, 6);
        c.ay = beWord(motion, 8);
        c.y = beWord(motion, 10);
        c.hold = 62;
        for (0..50) |i| c.history[i] = beWord(history, i * 2);
        return c;
    }

    pub fn step(self: *Clock) void {
        self.tick +%= 1;
        if (self.tick % 320 == 0) self.hold = 61;
        // copy(History[:49], History[1:]): shift left, History[49] set below.
        var i: usize = 0;
        while (i < 49) : (i += 1) self.history[i] = self.history[i + 1];
        if (self.hold > 0) {
            self.hold -= 1;
        } else {
            self.x = self.x +% self.vx;
            self.y = self.y +% self.vy;
            self.counter += 1;
            if (self.counter == 5) {
                self.counter = 0;
                self.vx = self.vx +% self.ax;
                self.vy = self.vy +% self.ay;
                if (self.vx == 6 or self.vx == -6) self.ax = 0 -% self.ax;
                if (self.vy == 3 or self.vy == -3) self.ay = 0 -% self.ay;
            }
        }
        self.history[49] = self.x;
    }
};
