// --------------------------------------------------------------------------
// Joystick state for Charly from the host's input events.
//
// melonJS reads keys as HELD (me.input.isKeyPressed). The ZigMachine host only
// sends key-DOWN events (auto-repeated by the browser) and no key-up, so a
// direction stays held for a window after each event: FIRST_HOLD frames after a
// fresh press, long enough to bridge the browser's initial repeat delay (~500
// ms), then REPEAT_HOLD once repeats flow (~33 ms apart). A tap therefore walks
// about half a second; a released key stops within REPEAT_HOLD frames.
// --------------------------------------------------------------------------
const Input = @import("charly.zig").Input;

const FIRST_HOLD: u8 = 30;
pub const REPEAT_HOLD: u8 = 4;
const K_F1: u32 = 0xE001; // host KEY_CODES.F1

pub const Controls = struct {
    hold: [4]u8, // frames left, indexed by host Direction: up, down, left, right
    fire: bool, // Space / Enter this frame ("enter" is bound with lock, main.js:391)
    fast: bool, // F1 or S this frame
    teleport: ?usize, // a digit or H this frame (entities.js:99-152)

    pub fn init(self: *Controls) void {
        self.hold = .{ 0, 0, 0, 0 };
        self.fire = false;
        self.fast = false;
        self.teleport = null;
    }

    /// Host Direction: 0 up, 1 down, 2 left, 3 right, 5 fire.
    pub fn input(self: *Controls, dir: u8) void {
        if (dir < 4) {
            const h = &self.hold[dir];
            h.* = if (h.* == 0) FIRST_HOLD else @max(h.*, REPEAT_HOLD);
        } else if (dir == 5) {
            self.fire = true;
        }
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
            .up = self.hold[0] > 0,
            .down = self.hold[1] > 0,
            .left = self.hold[2] > 0,
            .right = self.hold[3] > 0,
            .fast = self.fast,
            .teleport = self.teleport,
        };
    }

    /// End of frame: one-shot keys are spent, held windows count down.
    pub fn tick(self: *Controls) void {
        for (&self.hold) |*h| h.* -|= 1;
        self.fire = false;
        self.fast = false;
        self.teleport = null;
    }
};
