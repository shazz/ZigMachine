// --------------------------------------------------------------------------
// The incremental present (present.zig) against the full redraw it replaced
// (reference.zig), for 8,000 ticks: the 36-frame band many times over, the
// trail clock's bounces and the whole message window. Every few ticks the
// host is made to step twice before a present (MAX_TICKS), so the band diff
// also jumps two frames. On EVERY present the plane bytes must be identical.
//
//     zig test apps/zig/scene_tests.zig --test-filter larcociel2
// --------------------------------------------------------------------------
const std = @import("std");
const Clock = @import("clock.zig").Clock;
const textmod = @import("text.zig");
const present = @import("present.zig");
const ref = @import("reference.zig");

const N = present.W * present.H;
var plane: [N]u8 align(4) = undefined;
var want: [N]u8 = undefined;
var stream: textmod.Stream = undefined;

fn check(t: usize) !void {
    if (std.mem.eql(u8, &want, &plane)) return;
    const i = std.mem.indexOfDiff(u8, &want, &plane).?;
    std.debug.print("tick {d}: pixel ({d},{d}) is {d}, reference {d}\n", .{ t, i % present.W, i / present.W, plane[i], want[i] });
    return error.PresentDiverged;
}

test "larcociel2 incremental present == full redraw on every present, 8000 ticks" {
    var clock = Clock.init();
    stream.init();
    var p: present.Presenter = .{};
    @memset(&plane, 0xAA); // whatever the plane held before init
    const words: [*]u32 = @ptrCast(&plane);
    p.full(words, &clock, &stream, false);
    ref.present(&want, &clock, &stream, false);
    try check(0);
    var t: usize = 0;
    while (t < 8000) : (t += 1) {
        clock.step();
        stream.step();
        if (t % 7 == 3) { // a stalled host frame: two ticks, one present
            clock.step();
            stream.step();
        }
        p.update(words, &clock, &stream, true);
        ref.present(&want, &clock, &stream, true);
        try check(t);
    }
}
