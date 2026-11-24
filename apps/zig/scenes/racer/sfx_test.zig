// RACER: the sound effects' triggers (sfx.zig): each event's writes, the engine pitch, quiet frames, the cap.
const std = @import("std");
const sfx = @import("sfx.zig");

const Snap = sfx.Snap;

fn run(f: *sfx.Sfx, s: Snap) sfx.Out {
    var out: sfx.Out = .{};
    f.step(s, &out);
    return out;
}

fn has(out: sfx.Out, w: sfx.Write) bool {
    for (out.items()) |x| if (x.kind == w.kind and x.reg == w.reg and x.val == w.val) return true;
    return false;
}

const racing = Snap{ .racing = true, .state = .race, .ticks = 100 };

test "the engine keys on with its pitch when the car runs, follows the rpm, and keys off" {
    var f: sfx.Sfx = .{};
    var o = run(&f, racing);
    try std.testing.expect(has(o, .{ .kind = .ym0, .reg = 0x28, .val = 0xF6 })); // FM 6 keyed (code 6)
    try std.testing.expect(has(o, .{ .kind = .ym1, .reg = 0xA2, .val = @truncate(sfx.IDLE_FNUM) }));
    var s = racing;
    s.rpm = sfx.MAX_RPM;
    o = run(&f, s);
    try std.testing.expectEqual(@as(u32, 2), o.n); // the pitch pair only
    try std.testing.expectEqual(sfx.TOP_FNUM, f.fnum);
    s.rpm = sfx.MAX_RPM - 10; // a move under PITCH_STEP: nothing written
    try std.testing.expectEqual(@as(u32, 0), run(&f, s).n);
    o = run(&f, .{});
    try std.testing.expect(has(o, .{ .kind = .ym0, .reg = 0x28, .val = 0x06 }));
}

test "the engine pitch is clamped to its range for any rpm" {
    try std.testing.expectEqual(sfx.IDLE_FNUM, sfx.engineFnum(-5000));
    try std.testing.expectEqual(sfx.TOP_FNUM, sfx.engineFnum(1 << 30));
    try std.testing.expectEqual(@as(u32, 750), sfx.engineFnum(sfx.MAX_RPM / 2));
}

test "a knock retriggers the impact voice; a slide starts and stops the noise" {
    var f: sfx.Sfx = .{};
    _ = run(&f, racing);
    var s = racing;
    s.knocks = 1;
    var o = run(&f, s);
    try std.testing.expect(has(o, .{ .kind = .ym0, .reg = 0x28, .val = 0x05 }) and has(o, .{ .kind = .ym0, .reg = 0x28, .val = 0xF5 }));
    s.slide = true;
    o = run(&f, s);
    try std.testing.expect(has(o, .{ .kind = .psg, .val = 0xE5 }) and has(o, .{ .kind = .psg, .val = 0xF5 }));
    s.slide = false;
    o = run(&f, s);
    try std.testing.expect(has(o, .{ .kind = .psg, .val = 0xFF }));
}

test "the countdown beeps three times, then go; a checkpoint chimes; a lap and a win play their phrases" {
    const cd = Snap{ .racing = true, .state = .countdown };
    try std.testing.expect(sfx.cue(.{}, cd).?.ptr == &sfx.COUNT);
    try std.testing.expect(sfx.cue(.{ .state = .countdown, .ticks = 29 }, .{ .state = .countdown, .ticks = 30 }).?.ptr == &sfx.COUNT);
    try std.testing.expect(sfx.cue(.{ .state = .countdown, .ticks = 59 }, .{ .state = .countdown, .ticks = 61 }).?.ptr == &sfx.COUNT);
    try std.testing.expect(sfx.cue(.{ .state = .countdown, .ticks = 31 }, .{ .state = .countdown, .ticks = 32 }) == null);
    try std.testing.expect(sfx.cue(.{ .state = .countdown, .ticks = 89 }, .{ .state = .race }).?.ptr == &sfx.GO);
    try std.testing.expect(sfx.cue(.{ .state = .race, .gates = 1 }, .{ .state = .race, .gates = 2 }).?.ptr == &sfx.CHIME);
    try std.testing.expect(sfx.cue(.{ .state = .race, .gates = 3 }, .{ .state = .race, .gates = 4, .laps = 1 }).?.ptr == &sfx.LAP);
    try std.testing.expect(sfx.cue(.{ .state = .race, .laps = 2 }, .{ .state = .finish, .laps = 3, .outcome = .win }).?.ptr == &sfx.WIN);
    try std.testing.expect(sfx.cue(.{ .state = .race }, .{ .state = .finish, .outcome = .timeout }).?.ptr == &sfx.LOSE);
}

test "a phrase plays note by note on PSG tone 3 and ends silent" {
    var f: sfx.Sfx = .{};
    var s = Snap{ .state = .race, .gates = 0 };
    _ = run(&f, s);
    s.gates = 1;
    const o = run(&f, s); // E5: period 170 = 0xAA
    try std.testing.expect(has(o, .{ .kind = .psg, .val = 0xC0 | 0xA }) and has(o, .{ .kind = .psg, .val = 0x0A }));
    var frames: u32 = 0;
    var ended = false;
    while (frames < 40 and !ended) : (frames += 1) ended = has(run(&f, s), .{ .kind = .psg, .val = 0xDF });
    try std.testing.expect(ended);
    try std.testing.expectEqual(@as(u32, 6 + 14), frames); // the two notes' frames, then the silence
}

test "a quiet frame writes nothing, and a frame never writes more than the cap" {
    var f: sfx.Sfx = .{};
    _ = run(&f, .{});
    try std.testing.expectEqual(@as(u32, 0), run(&f, .{}).n);
    var out: sfx.Out = .{};
    for (0..sfx.Out.CAP + 5) |_| f.quiet(&out);
    var g: sfx.Sfx = .{};
    var full: sfx.Out = .{ .n = sfx.Out.CAP };
    g.step(.{ .racing = true, .state = .race, .knocks = 3 }, &full);
    try std.testing.expectEqual(@as(u32, sfx.Out.CAP), full.n);
    try std.testing.expect(full.dropped >= 4); // the engine's key + pitch and the impact pair: refused, counted
}

test "quiet silences what sounds and forgets the state" {
    var f: sfx.Sfx = .{};
    var s = racing;
    s.slide = true;
    _ = run(&f, s);
    var out: sfx.Out = .{};
    f.quiet(&out);
    try std.testing.expect(has(out, .{ .kind = .ym0, .reg = 0x28, .val = 0x06 }) and has(out, .{ .kind = .psg, .val = 0xFF }));
    try std.testing.expect(!f.engine and !f.skid);
}
