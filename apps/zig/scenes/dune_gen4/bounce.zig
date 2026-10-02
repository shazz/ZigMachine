// $43EA: a "3615 GEN4" letter's walk through BOUNCE. Up to index $AF, then
// down to 1 and up again; index 0 is only ever the start.
const A = @import("assets.zig");

const T = A.T;
pub const TURN = 0xAF; // BOUNCE's last index
/// From index 1 up to $AF and back down to 1: VBLs between two visits.
pub const PERIOD = 2 * (TURN - 1);

/// This VBL's height above line 100, and the next index.
pub fn advance(pos: *u16, up: *bool) u16 {
    if (up.*) {
        if (pos.* != TURN) {
            defer pos.* += 1;
            return T.BOUNCE[pos.*];
        }
        up.* = false;
    }
    if (pos.* == 1) {
        up.* = true;
        defer pos.* += 1;
        return T.BOUNCE[pos.*];
    }
    defer pos.* -= 1;
    return T.BOUNCE[pos.*];
}

comptime {
    // a start past the turn would walk up off the table's end
    for (T.LETTER_POS) |p| if (p > TURN) @compileError("a letter starts past BOUNCE's turn");
}

test "a letter walks BOUNCE up to $AF and back down to 1" {
    const std = @import("std");
    var pos: u16 = 0;
    var up = true;
    var seen: [400]u16 = undefined;
    for (&seen) |*s| s.* = advance(&pos, &up);
    try std.testing.expectEqual(@as(u16, T.BOUNCE[0]), seen[0]);
    try std.testing.expectEqual(@as(u16, T.BOUNCE[TURN]), seen[TURN]);
    try std.testing.expectEqual(@as(u16, T.BOUNCE[TURN - 1]), seen[TURN + 1]);
    try std.testing.expectEqual(@as(u16, T.BOUNCE[1]), seen[2 * TURN - 1]);
    try std.testing.expectEqual(seen[1], seen[1 + PERIOD]);
}
