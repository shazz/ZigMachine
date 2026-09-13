// --------------------------------------------------------------------------
// Joystick state for Charly from the host's input events.
//
// melonJS reads keys as HELD (me.input.isKeyPressed). Two hosts are possible:
//
// - One that sends key-UP (demo.inputRelease): a direction is held from its
//   press to its release, exactly as melonJS sees it. The first release switches
//   this mode on for good.
// - One that sends only key-DOWN, auto-repeated by the OS: a press after a pause
//   and then, while the key stays down, a repeat about every 33 ms after an
//   initial delay of about 500 ms. Held is then inferred from how recent the
//   last event is: FIRST_MS after a fresh press (long enough to bridge the
//   initial delay without a stutter), and only REPEAT_MS once repeats flow, so
//   a released key stops a couple of frames after its last repeat.
//
// Windows are in MILLISECONDS, not frames: the OS repeats in time. tick() is
// handed the length of the step it ends (the scene steps at 60 Hz).
// --------------------------------------------------------------------------
const Input = @import("charly.zig").Input;

const FIRST_MS: f32 = 550; // > the usual 500 ms initial repeat delay, by a frame and a half
const REPEAT_MS: f32 = 60; // > a 25-30 Hz repeat interval, plus a jittered frame
const K_F1: u32 = 0xE001; // host KEY_CODES.F1

pub const Controls = struct {
    held: [4]bool, // indexed by host Direction: up, down, left, right
    repeating: [4]bool, // an event arrived while the direction was still held
    since: [4]f32, // ms since the direction's last event
    releases: bool, // the host sends key-up: no inference
    fire: bool, // Space / Enter this frame ("enter" is bound with lock, main.js:391)
    fast: bool, // F1 or S this frame
    teleport: ?usize, // a digit or H this frame (entities.js:99-152)

    pub fn init(self: *Controls) void {
        self.held = .{ false, false, false, false };
        self.repeating = .{ false, false, false, false };
        self.since = .{ 0, 0, 0, 0 };
        self.releases = false;
        self.fire = false;
        self.fast = false;
        self.teleport = null;
    }

    /// Host Direction: 0 up, 1 down, 2 left, 3 right, 5 fire.
    pub fn input(self: *Controls, dir: u8) void {
        if (dir == 5) self.fire = true;
        if (dir >= 4) return;
        self.repeating[dir] = self.held[dir];
        self.held[dir] = true;
        self.since[dir] = 0;
    }

    /// Host key-up for a Direction.
    pub fn release(self: *Controls, dir: u8) void {
        self.releases = true;
        if (dir >= 4) return;
        self.held[dir] = false;
        self.repeating[dir] = false;
    }

    /// Character keys: F1/S speed up; 1-9, 0 and H teleport to the doors.
    pub fn key(self: *Controls, cp: u32) void {
        switch (cp) {
            K_F1, 'S', 's' => self.fast = true,
            '1'...'9' => self.teleport = cp - '1',
            '0' => self.teleport = 9,
            'H', 'h' => self.teleport = 10,
            else => {},
        }
    }

    pub fn state(self: *const Controls) Input {
        return .{
            .up = self.held[0],
            .down = self.held[1],
            .left = self.held[2],
            .right = self.held[3],
            .fast = self.fast,
            .teleport = self.teleport,
        };
    }

    /// End of frame: one-shot keys are spent; without key-up, a direction whose
    /// last event is older than its window is released.
    pub fn tick(self: *Controls, step_ms: f32) void {
        self.fire = false;
        self.fast = false;
        self.teleport = null;
        if (self.releases) return;
        for (&self.held, &self.repeating, &self.since) |*held, *repeating, *since| {
            if (!held.*) continue;
            since.* += step_ms;
            if (since.* >= (if (repeating.*) REPEAT_MS else FIRST_MS)) {
                held.* = false;
                repeating.* = false;
            }
        }
    }
};
