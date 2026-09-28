// --------------------------------------------------------------------------
// The remake's key bindings (main.js:87-95) from the host's input events:
//   LEFT / RIGHT  "left" / "right", held
//   UP            "fly", held (DOWN is not bound)
//   SPACE         "enter", bound with LOCK: me.input.isKeyPressed('enter') is
//                 true once per press, and only the door asks. A press is kept
//                 until a door takes it or the key comes up, so Space held
//                 while flying into the door still opens it.
//   ESC           "exit" (the scene's key())
//
// melonJS reads held keys. A host that sends key-up (demo.inputRelease) gives
// exactly that. One that sends only auto-repeated key-downs has "held" inferred
// from the last event's age, as the Union Demo hub does
// (union_demo/controls.zig): FIRST_MS bridges the OS's initial repeat delay,
// REPEAT_MS the repeat interval once repeats flow; and Space is then a one-step
// press, since its release can never be seen.
// --------------------------------------------------------------------------
const Input = @import("griffin.zig").Input;

const FIRST_MS: f32 = 550;
const REPEAT_MS: f32 = 60;
const UP: u8 = 0;
const LEFT: u8 = 2;
const RIGHT: u8 = 3;
const FIRE: u8 = 5;

pub const Controls = struct {
    held: [4]bool, // by host Direction: up, down, left, right
    repeating: [4]bool,
    since: [4]f32, // ms since the direction's last event
    releases: bool, // the host sends key-up
    enter: bool, // a Space press no door has taken yet
    enter_locked: bool, // taken: ignored until the key comes up

    pub fn init(self: *Controls) void {
        self.held = .{ false, false, false, false };
        self.repeating = .{ false, false, false, false };
        self.since = .{ 0, 0, 0, 0 };
        self.releases = false;
        self.enter = false;
        self.enter_locked = false;
    }

    /// Host Direction: 0 up, 1 down, 2 left, 3 right, 5 fire.
    pub fn input(self: *Controls, dir: u8) void {
        if (dir == FIRE and !self.enter_locked) self.enter = true;
        if (dir >= 4) return;
        self.repeating[dir] = self.held[dir];
        self.held[dir] = true;
        self.since[dir] = 0;
    }

    pub fn release(self: *Controls, dir: u8) void {
        self.releases = true;
        if (dir == FIRE) {
            self.enter = false;
            self.enter_locked = false;
        }
        if (dir >= 4) return;
        self.held[dir] = false;
        self.repeating[dir] = false;
    }

    pub fn state(self: *const Controls) Input {
        return .{ .left = self.held[LEFT], .right = self.held[RIGHT], .fly = self.held[UP] };
    }

    /// isKeyPressed('enter'), asked by a door the griffin touches.
    pub fn takeEnter(self: *Controls) bool {
        if (!self.enter) return false;
        self.enter = false;
        self.enter_locked = self.releases;
        return true;
    }

    /// End of a step: without key-up, a press is spent and a direction whose
    /// last event is older than its window is released.
    pub fn tick(self: *Controls, step_ms: f32) void {
        if (self.releases) return;
        self.enter = false;
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
