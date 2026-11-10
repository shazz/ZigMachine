// --------------------------------------------------------------------------
// NOTEPAD: a name typed in the ITEM SELECTOR made into the 8.3 name it saves as.
// --------------------------------------------------------------------------
const std = @import("std");

/// Upper case, spaces dropped, 12 characters at most, ".TXT" added when it has no dot.
pub fn txtName(typed: []const u8, buf: *[13]u8) []const u8 {
    var n: usize = 0;
    for (typed) |c| {
        if (n == 8 + 4 or c == ' ') continue;
        buf[n] = std.ascii.toUpper(c);
        n += 1;
    }
    if (n > 0 and std.mem.indexOfScalar(u8, buf[0..n], '.') == null and n <= 8) {
        @memcpy(buf[n .. n + 4], ".TXT");
        n += 4;
    }
    return buf[0..n];
}

test "a typed name becomes an 8.3 .TXT name" {
    var b: [13]u8 = undefined;
    try std.testing.expectEqualStrings("NOTES.TXT", txtName("notes", &b));
    try std.testing.expectEqualStrings("A.DOC", txtName("a.doc", &b));
    try std.testing.expectEqualStrings("README.TXT", txtName("ReadMe.txt", &b));
    try std.testing.expectEqualStrings("", txtName("", &b));
}
