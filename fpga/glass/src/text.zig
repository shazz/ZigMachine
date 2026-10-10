// Fitting text into the OSD's 32 columns: names cut with a '~', a long name
// scrolled (a marquee) when it is the one selected, descriptions word-wrapped.
const std = @import("std");

pub const CUT = '~'; // the ST font has no ellipsis in its low half

/// `s` if it fits in `width`, else its first width-1 characters and a '~'.
pub fn fit(buf: []u8, s: []const u8, width: usize) []const u8 {
    if (s.len <= width) return s;
    @memcpy(buf[0 .. width - 1], s[0 .. width - 1]);
    buf[width - 1] = CUT;
    return buf[0..width];
}

/// A `width` window onto `s` that slides one character a step, holds at each
/// end for two steps, and starts over; `s` itself if it fits.
pub fn marquee(s: []const u8, width: usize, phase: usize) []const u8 {
    if (s.len <= width) return s;
    const travel = s.len - width;
    const step = phase % (travel + 4);
    const off = if (step < 2) 0 else @min(step - 2, travel);
    return s[off..][0..width];
}

/// Greedy word wrap of `s` into `rows` of `width`; a word longer than a row is
/// cut. If it does not all fit, the last row ends in '~'. Returns rows used.
pub fn wrap(s: []const u8, width: usize, rows: [][]const u8, last_buf: []u8) usize {
    var rest = std.mem.trim(u8, s, " ");
    var n: usize = 0;
    while (rest.len > 0 and n < rows.len) : (n += 1) {
        var take = @min(rest.len, width);
        if (take < rest.len) {
            if (std.mem.lastIndexOfScalar(u8, rest[0 .. width + 1], ' ')) |sp| {
                if (sp > 0) take = sp;
            }
        }
        rows[n] = rest[0..take];
        rest = std.mem.trimStart(u8, rest[take..], " ");
    }
    if (rest.len > 0 and n > 0) {
        const last = rows[n - 1];
        const keep = @min(last.len, width - 1);
        @memcpy(last_buf[0..keep], last[0..keep]);
        last_buf[keep] = CUT;
        rows[n - 1] = last_buf[0 .. keep + 1];
    }
    return n;
}

/// A level as a bar of `cells`: '#' filled, '-' empty.
pub fn bar(buf: []u8, value: u32, max: u32, cells: usize) []const u8 {
    const filled = (value * cells + max / 2) / max;
    for (buf[0..cells], 0..) |*c, i| c.* = if (i < filled) '#' else '-';
    return buf[0..cells];
}

test "long names are cut or scrolled, descriptions wrapped" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("short", fit(&buf, "short", 8));
    try std.testing.expectEqualStrings("too lo~", fit(&buf, "too long a name", 7));
    try std.testing.expectEqualStrings("abcd", marquee("abcdef", 4, 0));
    try std.testing.expectEqualStrings("abcd", marquee("abcdef", 4, 1)); // holds
    try std.testing.expectEqualStrings("bcde", marquee("abcdef", 4, 3));
    try std.testing.expectEqualStrings("cdef", marquee("abcdef", 4, 5)); // holds at the end
    try std.testing.expectEqualStrings("abcd", marquee("abcdef", 4, 6)); // and starts over
    var rows: [2][]const u8 = undefined;
    try std.testing.expectEqual(@as(usize, 2), wrap("the quick brown fox", 9, &rows, &buf));
    try std.testing.expectEqualStrings("the quick", rows[0]);
    try std.testing.expectEqualStrings("brown fox", rows[1]);
    try std.testing.expectEqual(@as(usize, 2), wrap("the quick brown fox jumps", 9, &rows, &buf));
    try std.testing.expectEqualStrings("brown fo~", rows[1]);
    try std.testing.expectEqual(@as(usize, 0), wrap("", 9, &rows, &buf));
    try std.testing.expectEqualStrings("######--", bar(&buf, 191, 255, 8));
}
