// --------------------------------------------------------------------------
// TNT2's keys (screen.js:94-154), read the way melonJS reads them.
//
// '1'..'4' and 'left'/'right' are bound without a lock (main.js:360-379), so
// isKeyPressed is true on EVERY frame the key is held, and Left/Right change a
// speed once a frame. The host sends only key-down events, auto-repeated about
// every 33 ms after a ~500 ms delay, and no key-up: each event holds its key
// for HOLD frames, which bridges the repeats. A tap is two frames, a held key
// steps continuously once the browser repeats it.
//
// The branches are an else-if chain, so on a frame with several keys held only
// the first in chain order acts: 1, 2, 3, 4, then left, then right.
// --------------------------------------------------------------------------
pub const HOLD: u8 = 2;

pub const Action = enum(u8) { one, two, three, four, left, right };

pub const Controls = struct {
    hold: [6]u8, // frames left, by Action

    pub fn init(self: *Controls) void {
        self.hold = .{ 0, 0, 0, 0, 0, 0 };
    }

    pub fn press(self: *Controls, a: Action) void {
        self.hold[@intFromEnum(a)] = HOLD;
    }

    /// The key that acts this frame, if any.
    pub fn active(self: *const Controls) ?Action {
        for (self.hold, 0..) |h, i| if (h > 0) return @enumFromInt(i);
        return null;
    }

    /// End of frame: held windows count down.
    pub fn tick(self: *Controls) void {
        for (&self.hold) |*h| h.* -|= 1;
    }
};
