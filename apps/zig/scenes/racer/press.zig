// --------------------------------------------------------------------------
// RACER: fresh presses only, for the front end's Enter, Backspace and fire (M5 finish). The browser
// and glass both deliver a held key's auto-repeat as more presses, so holding Enter on the title used
// to walk title -> select -> race. The cart exports `keyUp` (racer.zig; both hosts already call a cart's
// keyUp when it has one, and inputRelease for fire), so a key counts once until it comes up.
// A host that never sends the release (or a release lost to a focus change) cannot lock a key: a key
// with no event for TIMEOUT frames counts as up, and a held key's repeats (every ~33 ms after a
// 250-500 ms delay) keep it down. No ZigOS import.
// --------------------------------------------------------------------------
pub const Key = enum(u2) { enter, backspace, fire };
pub const TIMEOUT: u32 = 45; // frames (750 ms): over any host's first repeat delay

pub var break_repeat = false; // racer_front.mjs --break repeat (key R): every repeat counts as a press

pub const Held = struct {
    at: [3]?u32 = .{ null, null, null }, // the frame of the key's last press event; null: up

    /// A press event of `k` at frame `now`: true when it is a fresh press (not a repeat of a held key).
    pub fn press(self: *Held, k: Key, now: u32) bool {
        const i = @intFromEnum(k);
        const fresh = if (self.at[i]) |t| now -% t > TIMEOUT else true;
        self.at[i] = now;
        return fresh or break_repeat;
    }

    pub fn release(self: *Held, k: Key) void {
        self.at[@intFromEnum(k)] = null;
    }
};

/// The key a code is (Enter 13, Backspace 8), or null.
pub fn ofCode(cp: u32) ?Key {
    return switch (cp) {
        13 => .enter,
        8 => .backspace,
        else => null,
    };
}
