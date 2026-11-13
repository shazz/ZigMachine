//! Tests for audio.zig (the mock): exact sample counts at 60 Hz, the clock reading
//! the sample source, a re-seek, and that the audio side sees a seek.
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const clock = @import("clock.zig");
const audio = @import("audio.zig");

test "sixty frames of 44.1 kHz are exactly one second of samples" {
    var m = audio.Music{};
    try expectEqual(@as(u32, 0), m.position());
    m.frame();
    try expectEqual(@as(u32, 735), m.position());
    for (0..59) |_| m.frame();
    try expectEqual(@as(u32, 44100), m.position());
}

test "the clock reads the music's position: 1 s of frames is 1000 ms" {
    var m = audio.Music{ .rate = 22050 };
    var c = clock.Clock{};
    c.update(m.source());
    for (0..60) |_| {
        m.frame();
        c.update(m.source());
    }
    try expectEqual(@as(u32, 1000), c.t);
}

test "a re-seek moves the stream to the seek's time" {
    var m = audio.Music{};
    m.seekMs(3000);
    try expectEqual(@as(u32, 180), m.frames);
    try expectEqual(@as(u32, 132300), m.position());
}

test "the audio side sees a clock seek through its own reader, and re-seeks" {
    var m = audio.Music{};
    var c = clock.Clock{};
    var r = clock.Reader{};
    c.update(m.source());
    try std.testing.expect(!r.changed(&c));
    c.jump(3000);
    try std.testing.expect(r.changed(&c));
    m.seekMs(c.t);
    c.update(m.source());
    try expectEqual(@as(u32, 3000), c.t);
}
