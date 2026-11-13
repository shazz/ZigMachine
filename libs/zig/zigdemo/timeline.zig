//! zigdemo timeline: TBL's sequencer (player/Timeline.h), made data-driven.
//!
//! A track is a sorted list of items. A `draw` item is the track's part from
//! its start until the next draw item (TBL's EachFrame). A `once` item fires its
//! part's `once` hook when playback crosses it going forward (TBL's Once);
//! going backward it fires nothing, and a jump does not fire it either.
//!
//! Where this differs from TBL, and why: a draw cursor skips `once` items (in
//! TBL a `once` item as the current item blanked the draw script); gather fires
//! every item crossed in one call (TBL moved one step a frame, so a hitch
//! dropped a load); and a jump on a load track replays its `once` items up to
//! the new time, so a seek lands with the same assets loaded as playing to it.
//!
//! No allocation: gather and jump report `once` items through a sink.

const std = @import("std");

pub const Kind = enum { draw, once };

pub const Item = struct {
    start_ms: u32,
    part: u16,
    kind: Kind,
    arg: u16 = 0,
};

pub const Track = struct {
    items: []const Item,
    /// A load track: jump() replays its once items up to the new time.
    replay_once: bool = false,
};

pub const Error = error{Unsorted};

/// The local time of a part: `now` minus its item's start. `now` must be at or
/// after the start, which the cursors guarantee.
pub fn localMs(item: Item, now: u32) u32 {
    std.debug.assert(now >= item.start_ms);
    return now - item.start_ms;
}

/// Items must not go back in time. Equal starts are allowed: both fire, in order.
pub fn validate(items: []const Item) Error!void {
    if (items.len < 2) return;
    for (items[1..], items[0 .. items.len - 1]) |b, a| {
        if (b.start_ms < a.start_ms) return error.Unsorted;
    }
}

/// The start of the first draw item after `now`, or null. What the debug
/// next-item key steps to.
pub fn nextDraw(items: []const Item, now: u32) ?u32 {
    for (items) |it| {
        if (it.kind == .draw and it.start_ms > now) return it.start_ms;
    }
    return null;
}

/// The start of the last draw item before `now`, or null. Strictly before, so
/// repeated presses keep stepping back.
pub fn prevDraw(items: []const Item, now: u32) ?u32 {
    var found: ?u32 = null;
    for (items) |it| {
        if (it.kind == .draw and it.start_ms < now) found = it.start_ms;
    }
    return found;
}

/// The index of the last item (of any kind) whose start is at or before `now`.
/// Items must be sorted.
fn lastAtOrBefore(items: []const Item, now: u32) ?usize {
    var i: usize = items.len;
    while (i > 0) : (i -= 1) {
        if (items[i - 1].start_ms <= now) return i - 1;
    }
    return null;
}

/// `n` is the number of tracks, fixed at comptime so the cursors need no allocation.
pub fn Timeline(comptime n: usize) type {
    return struct {
        const Self = @This();

        tracks: []const Track,
        /// Per track: the last item at or before the time; null before the first.
        pos: [n]?usize = [_]?usize{null} ** n,

        pub fn init(tracks: []const Track) Error!Self {
            std.debug.assert(tracks.len == n);
            for (tracks) |tr| try validate(tr.items);
            return .{ .tracks = tracks };
        }

        /// Moves every cursor to `now`. Forward: each `once` item crossed fires
        /// `sink.once(track, item)`, all of them and in order. Backward: the
        /// cursors move and nothing fires.
        pub fn gather(self: *Self, now: u32, sink: anytype) void {
            for (self.tracks, 0..) |tr, ti| {
                if (self.pos[ti]) |p| {
                    if (tr.items[p].start_ms > now) {
                        self.pos[ti] = lastAtOrBefore(tr.items, now);
                        continue;
                    }
                }
                var next: usize = if (self.pos[ti]) |p| p + 1 else 0;
                while (next < tr.items.len and tr.items[next].start_ms <= now) : (next += 1) {
                    const it = tr.items[next];
                    if (it.kind == .once) sink.once(ti, it);
                    self.pos[ti] = next;
                }
            }
        }

        /// A seek: every cursor goes to `now` without firing. The load tracks
        /// then replay their `once` items up to `now`, in order.
        pub fn jump(self: *Self, now: u32, sink: anytype) void {
            for (self.tracks, 0..) |tr, ti| {
                self.pos[ti] = lastAtOrBefore(tr.items, now);
                if (!tr.replay_once) continue;
                const last = self.pos[ti] orelse continue;
                for (tr.items[0 .. last + 1]) |it| {
                    if (it.kind == .once) sink.once(ti, it);
                }
            }
        }

        /// The index of the draw item playing on `track`: the last draw item at
        /// or before the cursor. Once items are skipped, since they never play.
        pub fn active(self: *const Self, track: usize) ?usize {
            const items = self.tracks[track].items;
            var i = self.pos[track] orelse return null;
            while (true) : (i -= 1) {
                if (items[i].kind == .draw) return i;
                if (i == 0) return null;
            }
        }
    };
}
