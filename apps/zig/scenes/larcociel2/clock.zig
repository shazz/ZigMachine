// --------------------------------------------------------------------------
// The trail clock -- internal/source/clock.go of go-larcociel2, transcribed
// statement for statement.
//
// A 66-point X/Y/Z history, SIGNED 16-BIT with the original's WRAPPING
// arithmetic (Go's `int16 +=`). Every Step shifts the history left and appends
// the new position; a three-tick velocity integrator accelerates at +-10/7/12
// on each axis and flips that axis's acceleration at the wall. The six ball
// slots sample History[i*11].
//
// The Go tree's own checkpoint (internal/source/testdata/native-motion-49.json)
// pins step 49; the headless harness asserts it against these very words.
// --------------------------------------------------------------------------
const assets = @import("assets.zig");

pub const Point = [3]i16;

pub const Clock = struct {
    tick: u32 = 0,
    counter: i32 = 0,
    velocity: Point = .{ 0, 0, 0 },
    acceleration: Point = .{ 0, 0, 0 },
    position: Point = .{ 0, 0, 0 },
    history: [66]Point = [_]Point{.{ 0, 0, 0 }} ** 66,

    fn word(b: []const u8, at: usize) i16 {
        return @bitCast(@as(u16, b[at]) << 8 | b[at + 1]);
    }

    /// motion 20 bytes (VX,VY,VZ, AX,AY,AZ, X,Y,Z, Counter), history 66*6.
    pub fn init() Clock {
        const motion = assets.initial_motion;
        const history = assets.initial_history;
        var c = Clock{};
        c.velocity = .{ word(motion, 0), word(motion, 2), word(motion, 4) };
        c.acceleration = .{ word(motion, 6), word(motion, 8), word(motion, 10) };
        c.position = .{ word(motion, 12), word(motion, 14), word(motion, 16) };
        c.counter = word(motion, 18);
        for (0..66) |i| {
            c.history[i] = .{ word(history, i * 6), word(history, i * 6 + 2), word(history, i * 6 + 4) };
        }
        return c;
    }

    pub fn step(self: *Clock) void {
        // copy(History[:65], History[1:]): shift left by one, History[65] set below.
        var i: usize = 0;
        while (i < 65) : (i += 1) self.history[i] = self.history[i + 1];
        self.position[0] +%= self.velocity[0];
        self.position[1] +%= self.velocity[1];
        self.position[2] +%= self.velocity[2];
        self.history[65] = self.position;
        self.counter += 1;
        if (self.counter == 3) {
            self.counter = 0;
            self.velocity[0] +%= self.acceleration[0];
            self.velocity[1] +%= self.acceleration[1];
            self.velocity[2] +%= self.acceleration[2];
            if (self.velocity[0] == 10 or self.velocity[0] == -10) self.acceleration[0] = 0 -% self.acceleration[0];
            if (self.velocity[1] == 7 or self.velocity[1] == -7) self.acceleration[1] = 0 -% self.acceleration[1];
            if (self.velocity[2] == 12 or self.velocity[2] == -12) self.acceleration[2] = 0 -% self.acceleration[2];
        }
        self.tick +%= 1;
    }
};
