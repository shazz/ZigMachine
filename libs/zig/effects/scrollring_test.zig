// Tests for effects/scrollring.zig: CODEF layout, wrap arithmetic (float and
// integer), text cycling, and that it reproduces the hand-written ring the
// ports used, frame for frame.
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const Ring = @import("scrollring.zig").Ring;

test "init lays letters out from start, one glyph apart, carrying the text in order" {
    const r = Ring(f32, 3).init("ABCDE", 100, 16);
    try expectEqual([3]f32{ 100, 116, 132 }, r.x);
    try expectEqual([3]u8{ 'A', 'B', 'C' }, r.c);
    try expectEqual(@as(u8, 'D'), r.upcoming());
}

test "a letter reaching -glyph_w rejoins at start + (x + glyph_w) with the next character" {
    var r = Ring(i32, 2).init("XYZ", 64, 64);
    r.x = .{ -60, 4 };
    try expectEqual(true, r.step(7)); // -67 <= -64 → 64 + (-67 + 64) = 61
    try expectEqual([2]i32{ 61, -3 }, r.x);
    try expectEqual([2]u8{ 'Z', 'Y' }, r.c);
    try expectEqual(false, r.step(1));
}

test "text index wraps to the start" {
    var r = Ring(i32, 1).init("AB", 0, 10);
    try expectEqual(@as(u8, 'B'), r.upcoming());
    _ = r.step(10); // 'B'
    _ = r.step(10); // 'A'
    try expectEqual(@as(u8, 'A'), r.c[0]);
    try expectEqual(@as(u8, 'B'), r.upcoming());
}

test "matches the hand-written f32 ring of noextra/supplex_fs2 over 5000 frames" {
    const N = 15;
    const GW: f32 = 26;
    const START: f32 = 14 * 26;
    const SPEED: f32 = 4.5;
    const TEXT = "HELLO WORLD] THIS IS A RING...";
    var ltr_x: [N]f32 = undefined;
    var ltr_c: [N]u8 = undefined;
    var off: usize = 0;
    for (0..N) |i| {
        ltr_x[i] = START + @as(f32, @floatFromInt(i)) * GW;
        ltr_c[i] = TEXT[off];
        off += 1;
        if (off > TEXT.len - 1) off = 0;
    }
    var r = Ring(f32, N).init(TEXT, START, GW);
    for (0..5000) |_| {
        for (0..N) |i| {
            ltr_x[i] -= SPEED;
            if (ltr_x[i] <= -GW) {
                ltr_x[i] = START + (ltr_x[i] + GW);
                ltr_c[i] = TEXT[off];
                off += 1;
                if (off > TEXT.len - 1) off = 0;
            }
        }
        _ = r.step(SPEED);
        for (0..N) |i| {
            try expectEqual(@as(u32, @bitCast(ltr_x[i])), @as(u32, @bitCast(r.x[i])));
            try expectEqual(ltr_c[i], r.c[i]);
        }
        try expectEqual(TEXT[off], r.upcoming());
    }
}

test "matches replicants_garfield's integer head model over 5000 frames" {
    const N = 22;
    const G: i32 = 64;
    const START: i32 = 21 * 64;
    const SPEED: i32 = 7;
    const TEXT = "GARFIELD SAYS HI ";
    var head_q: i32 = START;
    var head: usize = 0;
    var r = Ring(i32, N).init(TEXT, START, G);
    for (0..5000) |_| {
        head_q -= SPEED;
        if (head_q <= -G) {
            head_q += G;
            head = (head + 1) % TEXT.len;
        }
        _ = r.step(SPEED);
        // every head-model letter (x, char) exists in the ring
        for (0..N) |i| {
            const q = head_q + G * @as(i32, @intCast(i));
            const ch = TEXT[(head + i) % TEXT.len];
            var found = false;
            for (r.x, r.c) |x, c| {
                if (x == q and c == ch) found = true;
            }
            try std.testing.expect(found);
        }
    }
}
