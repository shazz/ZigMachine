// TEX COPIER's state machine against the remake running in Chrome: every expected
// value below is the JS object's field after that many update() calls, read from
// the reference capture (time, textureTime, currentText, nextText,
// fadeOutCompleted, isCopying, askToCopy, rasterScrollY, rasterTexture,
// scrollerRastersPos).
const std = @import("std");
const copier = @import("copier.zig");
const Copier = copier.Copier;

fn run(c: *Copier, frames: u32, space_at: u32) void {
    var f: u32 = c.global_time;
    while (f < frames) {
        f += 1;
        c.update(f == space_at);
    }
}

const Want = struct { time: u32, texture_time: u32, current: u8, next: u8, faded_out: bool, copying: bool, ask: u2, scroll2: i32, raster: u32, pos2: i32 };

fn expectState(c: *const Copier, w: Want) !void {
    try std.testing.expectEqual(w.time, c.time);
    try std.testing.expectEqual(w.texture_time, c.texture_time);
    try std.testing.expectEqual(w.current, c.current_text);
    try std.testing.expectEqual(w.next, c.next_text);
    try std.testing.expectEqual(w.faded_out, c.fade_out_completed);
    try std.testing.expectEqual(w.copying, c.is_copying);
    try std.testing.expectEqual(w.ask, c.ask_to_copy);
    try std.testing.expectEqual(w.scroll2, c.raster_scroll2);
    try std.testing.expectEqual(w.raster, c.raster_texture);
    try std.testing.expectEqual(w.pos2, c.pos2);
}

test "the rasters stay off for 103 frames, then restart every 104 on the next image" {
    var c: Copier = undefined;
    c.init();
    run(&c, 103, 0);
    try expectState(&c, .{ .time = 103, .texture_time = 103, .current = 0, .next = 0, .faded_out = true, .copying = false, .ask = 0, .scroll2 = 515, .raster = 0, .pos2 = -1177 });
    try std.testing.expect(!c.time_to_raster);
    run(&c, 104, 0);
    try std.testing.expect(c.time_to_raster);
    try expectState(&c, .{ .time = 104, .texture_time = 104, .current = 0, .next = 0, .faded_out = true, .copying = false, .ask = 0, .scroll2 = 0, .raster = 1, .pos2 = -1176 });
    run(&c, 209, 0);
    try std.testing.expectEqual(@as(u32, 2), c.raster_texture);
    try std.testing.expectEqual(@as(i32, 5), c.raster_scroll2);
}

test "a line fades out at 420 and the next fades in once the fade out completes" {
    var c: Copier = undefined;
    c.init();
    run(&c, 420, 0);
    try expectState(&c, .{ .time = 420, .texture_time = 0, .current = 0, .next = 1, .faded_out = false, .copying = false, .ask = 0, .scroll2 = 20, .raster = 4, .pos2 = -860 });
    try std.testing.expectEqual(@as(u8, 0), c.level);
    run(&c, 440, 0);
    try std.testing.expectEqual(@as(u8, 4), c.level); // fading out: textureTime 20 is level 4
    run(&c, 460, 0);
    try expectState(&c, .{ .time = 460, .texture_time = 0, .current = 1, .next = 1, .faded_out = true, .copying = false, .ask = 0, .scroll2 = 220, .raster = 4, .pos2 = -820 });
    try std.testing.expectEqual(@as(u8, 7), c.level); // fading in from nothing
}

test "space fades the line out, then the orange copy message fades in and stays" {
    var c: Copier = undefined;
    c.init();
    run(&c, 301, 300);
    try expectState(&c, .{ .time = 1, .texture_time = 0, .current = 0, .next = 0, .faded_out = false, .copying = false, .ask = 2, .scroll2 = 465, .raster = 2, .pos2 = -979 });
    run(&c, 341, 300);
    try expectState(&c, .{ .time = 41, .texture_time = 0, .current = 0, .next = 0, .faded_out = true, .copying = true, .ask = 2, .scroll2 = 145, .raster = 3, .pos2 = -939 });
    run(&c, 381, 300);
    try std.testing.expectEqual(copier.Set.orange, c.set);
    try std.testing.expectEqual(@as(u8, 0), c.level);
    try std.testing.expectEqualStrings(" PLEASE INSERT WRT-PROTECTED SOURCE-DISK ", c.line().?);
    // Space again changes the counter it resets, never the message
    run(&c, 1000, 700);
    try std.testing.expect(c.is_copying);
    try std.testing.expectEqual(@as(u8, 0), c.current_text);
    try std.testing.expectEqual(@as(u32, 659), c.texture_time);
}

test "the missing text[29] keeps its 7-second slot and draws no line" {
    var c: Copier = undefined;
    c.init();
    run(&c, 29 * copier.LINE_FRAMES + 41, 0);
    try std.testing.expectEqual(@as(u8, 29), c.current_text);
    try std.testing.expect(c.line() == null);
    run(&c, 12650, 0);
    try std.testing.expectEqual(@as(u8, 30), c.current_text);
    try std.testing.expectEqual(@as(u32, 10), c.texture_time);
    try std.testing.expect(c.line() != null);
}

test "after the last line the text starts over from line 0" {
    var c: Copier = undefined;
    c.init();
    run(&c, 34 * copier.LINE_FRAMES, 0);
    try std.testing.expectEqual(@as(u32, 0), c.time); // index 34 > text.length - 1
    try std.testing.expectEqual(@as(u8, 34), c.next_text);
    run(&c, 34 * copier.LINE_FRAMES + 41, 0);
    try std.testing.expectEqual(@as(u8, 0), c.current_text);
}

test "the texture position wraps from 0 back to -640" {
    var c: Copier = undefined;
    c.init();
    run(&c, 1279, 0);
    try std.testing.expectEqual(@as(i32, -1), c.pos2);
    run(&c, 1280, 0);
    try std.testing.expectEqual(@as(i32, -1280), c.pos2);
}
