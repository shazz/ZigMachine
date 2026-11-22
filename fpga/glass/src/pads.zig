// The USB pads, one Pad per evdev node (R83: two joysticks, one per player).
//
// A node is keyed by its event number (`/dev/input/eventN`, evdev.Device.num), which survives a
// rescan; players are assigned in the order the pads were first heard from: the first is player
// 1 (REG_JOY, the cart's input()), the second player 2 (the key FIFO's KEY_P2_STATE word, the
// cart's input2(); map.zig "player 2"). A third and later pad drives the OSD only. A node that
// stays silent never takes a slot, so a keyboard-only receiver does not eat player 1.
const std = @import("std");
const map = @import("map.zig");
const pad = @import("pad.zig");

pub const MAX_PADS = 4;
const MAX_LOGGED = 16; // distinct unknown codes logged in all: a noisy device cannot flood the log

pub const Slot = struct { num: u16, pad: pad.Pad = .{} };

pub const Pads = struct {
    slots: [MAX_PADS]Slot = undefined,
    n: usize = 0,
    sent: [2]u32 = .{ 0, 0 }, // what the cart was last told, per player
    logged: [MAX_LOGGED]u32 = undefined, // type << 16 | code, as already logged
    n_logged: usize = 0,

    /// The slot of event node `num`, taking the next free one the first time it is heard. When
    /// all are taken an idle pad's slot is dropped (a pad re-plugged as another node); null:
    /// every pad is held down, so this one is ignored.
    pub fn slot(self: *Pads, num: u16) ?usize {
        for (self.slots[0..self.n], 0..) |s, i| if (s.num == num) return i;
        if (self.n == MAX_PADS) {
            const idle = for (self.slots[0..self.n], 0..) |s, i| {
                if (s.pad.bits == 0) break i;
            } else return null;
            std.mem.copyForwards(Slot, self.slots[idle .. self.n - 1], self.slots[idle + 1 .. self.n]);
            self.n -= 1;
        }
        self.slots[self.n] = .{ .num = num };
        self.n += 1;
        return self.n - 1;
    }

    /// The bits player `p` (0 or 1) holds: its pad's, 0 with no such pad.
    pub fn player(self: *const Pads, p: usize) u32 {
        return if (p < self.n) self.slots[p].pad.bits else 0;
    }

    /// True the first time an event the pad parser does not know is seen (for the log), at most
    /// MAX_LOGGED times in all.
    pub fn firstUnknown(self: *Pads, ev_type: u16, code: u16) bool {
        if (pad.known(ev_type, code)) return false;
        const key = @as(u32, ev_type) << 16 | code;
        for (self.logged[0..self.n_logged]) |k| if (k == key) return false;
        if (self.n_logged == MAX_LOGGED) return false;
        self.logged[self.n_logged] = key;
        self.n_logged += 1;
        return true;
    }
};

/// Player 2's state as the word the cart CPU's firmware reads from the key FIFO.
pub fn p2Word(bits: u32) u32 {
    return map.KEY_P2_STATE | (bits & map.KEY_P2_MASK);
}
