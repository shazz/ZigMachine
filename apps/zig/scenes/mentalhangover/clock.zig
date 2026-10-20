// --------------------------------------------------------------------------
// The circle clock, straight from internal/demo/circle_clock.go and DCK's
// scrolltext.ByteWindow (v1.0.13).
//
// The production advances one step per 50 Hz frame:
//
//   phase 0  33 fade-in steps      level = local
//   phase 1  the active screen     radius/profile phases, 11 row offsets,
//                                  the 8-byte lookahead window
//   phase 2  33 fade-out steps     level = 32 - local, text already gone
//
// The window is 8 slots wide and moves its byte position by -2 a step; with
// Crossing=NonNegative it advances the cursor when the signed position goes
// non-negative (i.e. at the $80/$00 wrap).  A `|` payload pauses for
// (v-32)*25 ticks; a `>` payload installs the five transport bytes.  The text
// bank's terminator is $ff and is never displayed.
//
// The clock fixture internal/demo/testdata/original-circle-clock.csv -- the
// original machine's words for all 3274 active steps -- is pinned by the
// harness, so this transport is checked against the production's own CPU
// trace, not just against a re-reading of the Go source.
// --------------------------------------------------------------------------
const A = @import("assets.zig");

pub const SLOTS: usize = 8;
pub const ROWS: usize = 11;

pub const Pt = struct { x: i16, y: i16 };

pub const Clock = struct {
    phase: u8 = 0,
    local: i32 = -1,
    angle: u8 = 0,
    cursor: u16 = 0,
    pause: i32 = 0,
    radius_phase: u8 = 64,
    profile_phase: u8 = 192,
    radius_step: u8 = 2,
    factor: u8 = 22,
    profile_step: u8 = 4,
    base: i32 = 0,
    rows: [ROWS]i32 = @splat(0),
    letters: [SLOTS]u8 = @splat(0),
    level: u8 = 0,
    active: bool = false,
    done: bool = false,
    tick: u32 = 0,

    position: u8 = 0,
    next: [A.TEXT.len]u16 = undefined,
    finished: bool = false,

    pub fn init() Clock {
        var c: Clock = .{};
        c.buildNext();
        return c;
    }

    fn buildNext(self: *Clock) void {
        var index: i32 = @intCast(A.TERMINAL);
        while (index >= 0) : (index -= 1) {
            const i: usize = @intCast(index);
            self.next[i] = @intCast(i);
            const v = A.TEXT[i];
            if (v >= 128) continue;
            if (v == '|' or v == '>') {
                const payload: usize = if (v == '|') 1 else 5;
                const destination = i + 1 + payload;
                if (destination > A.TERMINAL) {
                    self.next[i] = @intCast(A.TERMINAL);
                } else {
                    self.next[i] = self.next[destination];
                }
            }
        }
    }

    pub fn step(self: *Clock) bool {
        if (self.done) return false;
        self.tick += 1;
        self.local += 1;
        if (self.phase == 0) {
            self.level = @intCast(self.local);
            if (self.local == 32) {
                self.phase = 1;
                self.local = -1;
            }
            return true;
        }
        if (self.phase == 2) {
            self.level = @intCast(32 - self.local);
            if (self.local == 32) self.done = true;
            return true;
        }
        self.active = true;
        self.radius_phase +%= self.radius_step;
        self.profile_phase +%= self.profile_step;
        const p: i32 = A.profileAt(self.radius_phase);
        self.base = ((p + 127) * @as(i32, self.factor) & 0xff00) >> 8;
        const w: i32 = A.waveAt(self.profile_phase);
        for (0..ROWS) |i| {
            const k: i32 = 20 - @as(i32, @intCast(i)) * 4;
            self.rows[i] = (k * w >> 7) + 20;
        }
        self.windowStep();
        if (self.finished) self.finish();
        return true;
    }

    fn finish(self: *Clock) void {
        self.phase = 2;
        self.local = -1;
        self.active = false;
        self.level = 32;
    }

    fn windowStep(self: *Clock) void {
        if (self.finished) return;
        if (self.pause > 0) {
            self.pause -= 1;
        } else {
            self.position +%= @as(u8, @bitCast(@as(i8, -2)));
            var crossed = @as(i8, @bitCast(self.position)) < 0;
            crossed = !crossed; // Crossing = NonNegative
            if (crossed) {
                self.position +%= @as(u8, 30);
                if (@as(usize, self.cursor) < A.TERMINAL) self.cursor += 1;
                self.consume();
            }
        }
        self.angle = self.position;
        var index: usize = self.cursor;
        for (0..SLOTS) |slot| {
            if (index <= A.TERMINAL) index = self.next[index];
            if (index > A.TERMINAL or A.TEXT[index] >= 128) {
                self.finished = true;
                return;
            }
            self.letters[slot] = A.TEXT[index];
            index += 1;
        }
    }

    fn consume(self: *Clock) void {
        var guard: usize = 0;
        while (guard <= A.TERMINAL) : (guard += 1) {
            if (@as(usize, self.cursor) >= A.TERMINAL or A.TEXT[@as(usize, self.cursor)] >= 128) return;
            const v = A.TEXT[@as(usize, self.cursor)];
            if (v == '|') {
                const pause: i32 = (@as(i32, A.TEXT[@as(usize, self.cursor) + 1]) - 32) * 25;
                if (pause > 0) self.pause = pause;
                self.cursor += 2;
            } else if (v == '>') {
                self.radius_step = A.TEXT[@as(usize, self.cursor) + 1];
                self.factor = A.TEXT[@as(usize, self.cursor) + 2];
                self.profile_step = A.TEXT[@as(usize, self.cursor) + 3];
                self.radius_phase = A.TEXT[@as(usize, self.cursor) + 4];
                self.profile_phase = A.TEXT[@as(usize, self.cursor) + 5];
                self.cursor += 6;
            } else return;
        }
    }

    /// circle_clock.go's Point(): slot+1 puts the eight glyphs on 30-degree
    /// spokes, the projection's centre is (173,108) and the radius is
    /// (base + rows[row]) * 2.
    pub fn point(self: *const Clock, slot: usize, p: A.Point) Pt {
        const angle: i64 = @as(i64, self.angle) + 100 +
            (@as(i64, @intCast(slot)) + 1) * 30 + @as(i64, p.angle);
        const radius: i64 = @as(i64, self.base + self.rows[@as(usize, p.row)]) * 2;
        return polar(angle, radius);
    }
};

/// motion.TablePolar.Point with Shift=7, Center=(173,108), Phases=(0,64),
/// WordBits=16.  Every step is int64 in the Go; the ranges here fit, and the
/// two sign-wraps are kept because they are visible at the table's edges.
fn polar(angle: i64, radius: i64) Pt {
    var axes: [2]i64 = undefined;
    for (0..2) |axis| {
        const phase: u64 = if (axis == 0) 0 else 64;
        const idx: usize = @intCast((phase -% @as(u64, @bitCast(angle))) & 255);
        axes[axis] = (@as(i64, A.waveAt(@intCast(idx))) * radius) >> 7;
    }
    const x = sign16(sign16(axes[0]) + 173);
    const y = sign16(sign16(axes[1]) + 108);
    return .{ .x = @intCast(x), .y = @intCast(y) };
}

fn sign16(v: i64) i64 {
    const low: u16 = @truncate(@as(u64, @bitCast(v)));
    return @as(i16, @bitCast(low));
}
