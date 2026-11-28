// RACER: the effects' PSG-only layout (sfx_psg.zig, board batch item 2): every write on the PSG channels it owns.
const std = @import("std");
const sfx = @import("sfx.zig");
const psg = @import("sfx_psg.zig");

const Snap = sfx.Snap;
const racing = Snap{ .racing = true, .state = .race, .ticks = 100 };

fn run(f: *sfx.Sfx, s: Snap) sfx.Out {
    var out: sfx.Out = .{};
    f.step(s, &out);
    return out;
}

fn has(out: sfx.Out, val: u8) bool {
    for (out.items()) |x| if (x.kind == .psg and x.val == val) return true;
    return false;
}

/// No FM write ever, and every PSG latch byte on a channel the mask owns (tone 1 = 0, tone 3 = 2, the noise = 3).
fn onlyOwned(out: sfx.Out) bool {
    for (out.items()) |x| {
        if (x.kind != .psg) return false;
        if (x.val & 0x80 != 0 and (psg.MASK >> @intCast(8 + ((x.val >> 5) & 3))) & 1 == 0) return false;
    }
    return true;
}

test "the engine is PSG tone 1: its period follows the rpm, and it is silenced when the car stops" {
    var f: sfx.Sfx = .{ .layout = .psg };
    var o = run(&f, racing);
    try std.testing.expect(has(o, 0x80 | (psg.IDLE_PERIOD & 15)) and has(o, psg.IDLE_PERIOD >> 4) and has(o, 0x90 | psg.ENGINE_ATT));
    try std.testing.expect(onlyOwned(o));
    var s = racing;
    s.rpm = sfx.MAX_RPM;
    o = run(&f, s);
    try std.testing.expectEqual(@as(u32, 2), o.n); // the period pair only
    try std.testing.expectEqual(psg.TOP_PERIOD, f.fnum);
    o = run(&f, .{});
    try std.testing.expect(has(o, 0x9F)); // tone 1 at attenuation 15
}

test "the period is clamped to its range for any rpm (a negative or huge rpm never wraps)" {
    try std.testing.expectEqual(psg.IDLE_PERIOD, psg.enginePeriod(-5000));
    try std.testing.expectEqual(psg.TOP_PERIOD, psg.enginePeriod(1 << 30));
    try std.testing.expectEqual(@as(u32, 690), psg.enginePeriod(sfx.MAX_RPM / 2));
}

test "a knock is a noise burst that fades, then a slide's hiss takes the noise back" {
    var f: sfx.Sfx = .{ .layout = .psg };
    _ = run(&f, racing);
    var s = racing;
    s.knocks = 1;
    s.slide = true;
    const o = run(&f, s);
    try std.testing.expect(has(o, 0xE4) and has(o, 0xF0) and onlyOwned(o));
    var last: u8 = 0;
    for (0..sfx.IMPACT_FRAMES - 1) |_| {
        const fo = run(&f, s);
        for (fo.items()) |x| if (x.val & 0xF0 == 0xF0) {
            try std.testing.expect(x.val & 15 >= last); // the burst only ever fades
            last = x.val & 15;
        };
    }
    const end = run(&f, s);
    try std.testing.expect(has(end, 0xE5) and has(end, 0xF5)); // the burst over: the skid's noise again
}

test "quiet silences the PSG layout and keeps the layout; no FM key-off is written" {
    var f: sfx.Sfx = .{ .layout = .psg };
    var s = racing;
    s.slide = true;
    _ = run(&f, s);
    var out: sfx.Out = .{};
    f.quiet(&out);
    try std.testing.expect(has(out, 0x9F) and has(out, 0xFF) and onlyOwned(out));
    try std.testing.expect(!f.engine and !f.skid and f.layout == .psg);
}

test "a full frame drops (counts) the PSG layout's writes instead of overflowing" {
    var f: sfx.Sfx = .{ .layout = .psg };
    var full: sfx.Out = .{ .n = sfx.Out.CAP };
    f.step(.{ .racing = true, .state = .race, .knocks = 3 }, &full);
    try std.testing.expectEqual(@as(u32, sfx.Out.CAP), full.n);
    try std.testing.expect(full.dropped >= 5); // the engine's period pair + volume and the burst's pair
}

test "the mask owns PSG 1, 3 and the noise only: no FM channel, nothing the 32X tunes play" {
    try std.testing.expectEqual(@as(u32, 0), psg.MASK & 0x3F);
    try std.testing.expectEqual(@as(u32, 0), psg.MASK & (1 << 9)); // PSG tone 2 stays the tune's
}
