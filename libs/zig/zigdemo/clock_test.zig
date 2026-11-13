//! Tests for clock.zig: the sources, pause, seek, A-B loop, the reader, the u32 wrap.
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const clock = @import("clock.zig");

const Clock = clock.Clock;

test "samples source: one second of audio is 1000 ms" {
    var c = Clock{};
    c.update(.{ .samples = .{ .rate = 44100, .fed = 44100, .fill = 0 } });
    try expectEqual(@as(u32, 0), c.t); // the first reading anchors the clock at 0
    c.update(.{ .samples = .{ .rate = 44100, .fed = 88200, .fill = 0 } });
    try expectEqual(@as(u32, 1000), c.t);
}

test "samples source: the ring's fill is not time" {
    var c = Clock{};
    c.update(.{ .samples = .{ .rate = 44100, .fed = 0, .fill = 0 } });
    c.update(.{ .samples = .{ .rate = 44100, .fed = 44100, .fill = 22050 } });
    try expectEqual(@as(u32, 500), c.t); // 44100 fed, 22050 still in the ring: 22050 played, 500 ms
}

test "song_ms and vbl sources follow their deltas" {
    var c = Clock{};
    c.update(.{ .song_ms = 1000 });
    c.update(.{ .song_ms = 1500 });
    try expectEqual(@as(u32, 500), c.t);
    var v = Clock{};
    v.update(.{ .vbl = .{ .count = 100, .hz = 50 } });
    v.update(.{ .vbl = .{ .count = 125, .hz = 50 } });
    try expectEqual(@as(u32, 500), v.t);
}

test "frame index is 60 Hz, from t" {
    var c = Clock{ .t = 16 };
    try expectEqual(@as(u32, 0), c.frame());
    c.t = 17;
    try expectEqual(@as(u32, 1), c.frame());
    c.t = 1000;
    try expectEqual(@as(u32, 60), c.frame());
}

test "a clock starts at 0 whatever its source reads" {
    var c = Clock{};
    c.update(.{ .song_ms = 5000 });
    try expectEqual(@as(u32, 0), c.t);
}

test "pause holds t while the source runs; resume continues without a jump" {
    var c = Clock{};
    c.update(.{ .song_ms = 1000 }); // the first reading anchors t at 0
    c.update(.{ .song_ms = 2000 });
    try expectEqual(@as(u32, 1000), c.t);
    c.setPaused(true);
    c.update(.{ .song_ms = 3000 });
    try expectEqual(@as(u32, 1000), c.t);
    c.setPaused(false);
    c.update(.{ .song_ms = 3000 }); // the resume frame re-anchors
    try expectEqual(@as(u32, 1000), c.t);
    c.update(.{ .song_ms = 3100 });
    try expectEqual(@as(u32, 1100), c.t);
    try expectEqual(@as(u32, 0), c.seq); // a pause is not a seek
}

test "jump sets t and holds it on the next frame, then playback follows the source; seq counts it" {
    var c = Clock{};
    c.update(.{ .song_ms = 1000 });
    c.update(.{ .song_ms = 1200 });
    c.jump(5000);
    try expectEqual(@as(u32, 5000), c.t);
    c.update(.{ .song_ms = 1300 }); // the seek's frame re-anchors at the seek's time
    try expectEqual(@as(u32, 5000), c.t);
    c.update(.{ .song_ms = 1400 });
    try expectEqual(@as(u32, 5100), c.t);
    try expectEqual(@as(u32, 1), c.seq);
}

test "jump backward and to 0 are allowed" {
    var c = Clock{};
    c.update(.{ .song_ms = 0 });
    c.update(.{ .song_ms = 9000 });
    c.jump(0);
    c.update(.{ .song_ms = 9010 });
    try expectEqual(@as(u32, 0), c.t);
    c.update(.{ .song_ms = 9020 });
    try expectEqual(@as(u32, 10), c.t);
}

test "paused jump holds the new time" {
    var c = Clock{};
    c.update(.{ .song_ms = 0 });
    c.setPaused(true);
    c.jump(4000);
    c.update(.{ .song_ms = 7000 });
    try expectEqual(@as(u32, 4000), c.t);
}

test "reader sees each seek once and does not steal it from another reader" {
    var c = Clock{};
    var demo_r = clock.Reader{};
    var audio_r = clock.Reader{};
    c.jump(100);
    try std.testing.expect(demo_r.changed(&c));
    try std.testing.expect(!demo_r.changed(&c));
    try std.testing.expect(audio_r.changed(&c));
    try std.testing.expect(!audio_r.changed(&c));
}

test "A-B loop: reaching b goes back to a, exactly at b included" {
    var c = Clock{};
    c.setLoop(1000, 2000);
    c.update(.{ .song_ms = 0 });
    c.update(.{ .song_ms = 1900 });
    try expectEqual(@as(u32, 1900), c.t);
    c.update(.{ .song_ms = 2000 });
    try expectEqual(@as(u32, 1000), c.t);
    try expectEqual(@as(u32, 1), c.seq); // the wrap is the one discontinuity
    c.update(.{ .song_ms = 2100 }); // the wrap's frame holds at a
    try expectEqual(@as(u32, 1000), c.t);
    c.update(.{ .song_ms = 2200 });
    try expectEqual(@as(u32, 1100), c.t);
}

test "A-B loop: a loop that did not reach b does not wrap, and a cleared loop never does" {
    var c = Clock{};
    c.setLoop(1000, 2000);
    c.update(.{ .song_ms = 0 });
    c.update(.{ .song_ms = 1999 });
    try expectEqual(@as(u32, 1999), c.t);
    c.clearLoop();
    c.update(.{ .song_ms = 2500 });
    try expectEqual(@as(u32, 2500), c.t);
}

test "a seek past b is not a wrap: the loop only catches playback" {
    var c = Clock{};
    c.setLoop(1000, 2000);
    c.update(.{ .song_ms = 0 });
    c.jump(3000);
    c.update(.{ .song_ms = 0 });
    try expectEqual(@as(u32, 3000), c.t);
}

test "t keeps counting across a u32 wrap of the source" {
    var c = Clock{};
    c.update(.{ .song_ms = 0xFFFF_FF00 });
    c.update(.{ .song_ms = 0x0000_0100 });
    try expectEqual(@as(u32, 0x200), c.t);
}

test "changing the time base keeps t and is not a seek" {
    var c = Clock{};
    c.update(.{ .samples = .{ .rate = 44100, .fed = 0, .fill = 0 } });
    c.update(.{ .samples = .{ .rate = 44100, .fed = 44100, .fill = 0 } });
    try expectEqual(@as(u32, 1000), c.t);
    c.update(.{ .song_ms = 5000 });
    try expectEqual(@as(u32, 1000), c.t);
    c.update(.{ .song_ms = 5100 });
    try expectEqual(@as(u32, 1100), c.t);
    try expectEqual(@as(u32, 0), c.seq);
}
