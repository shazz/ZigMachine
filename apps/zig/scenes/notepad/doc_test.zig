// NOTEPAD's document (doc.zig): editing, cursor moves, the clipboard, find. Native (scene_tests.zig).
const std = @import("std");
const doc = @import("doc.zig");
const Doc = doc.Doc;
const Text = doc.Text;
const testing = std.testing;

const Fixture = struct {
    buf: [128]u8 = undefined,
    st: [16]u32 = undefined,
    clip: [32]u8 = undefined,
    fn doc(self: *Fixture) Doc {
        return .{ .text = Text.init(&self.buf, &self.st), .clip = &self.clip };
    }
};

test "typing, Return and Backspace edit at the cursor and mark the lines" {
    var f = Fixture{};
    var d = f.doc();
    for ("hi") |c| try d.typeChar(c);
    try d.typeChar('\n');
    try d.typeChar('x');
    try testing.expectEqualStrings("hi\nx", d.text.bytes());
    try testing.expect(d.touched.to_end and d.modified);
    d.backspace();
    d.backspace();
    try testing.expectEqualStrings("hi", d.text.bytes());
    try testing.expectEqual(@as(u32, 2), d.cursor);
}

test "arrows keep the column across a short line; Shift selects" {
    var f = Fixture{};
    var d = f.doc();
    try d.replace("abcdef\nab\nabcdef");
    d.moveTo(5, false);
    d.want_col = 5;
    d.vertical(true, 1, false);
    try testing.expectEqual(@as(u32, 9), d.cursor); // end of "ab"
    d.vertical(true, 1, true);
    try testing.expectEqual(@as(u32, 15), d.cursor); // column 5 again
    try testing.expectEqual(@as(u32, 9), d.anchor);
    d.left(false); // collapses to the selection's start
    try testing.expectEqual(@as(u32, 9), d.cursor);
}

test "cut, paste and the clipboard" {
    var f = Fixture{};
    var d = f.doc();
    try d.replace("one two");
    d.moveTo(0, false);
    d.moveTo(4, true);
    d.cut();
    try testing.expectEqualStrings("two", d.text.bytes());
    d.end(false);
    try d.paste();
    try testing.expectEqualStrings("twoone ", d.text.bytes());
}

test "a paste past the limit is an error and changes nothing" {
    var f = Fixture{};
    var d = f.doc();
    d.text.buf = f.buf[0..8];
    try d.replace("1234567");
    d.selectAll();
    d.copy();
    d.end(false);
    try testing.expectError(error.Full, d.paste());
    try testing.expectEqualStrings("1234567", d.text.bytes());
}

test "find selects the next match, case folded, wrapping once" {
    var f = Fixture{};
    var d = f.doc();
    try d.replace("Alpha beta ALPHA");
    d.moveTo(0, false);
    try testing.expect(d.find("alpha"));
    try testing.expectEqual(@as(u32, 0), d.selLo());
    try testing.expect(d.find("alpha"));
    try testing.expectEqual(@as(u32, 11), d.selLo());
    try testing.expect(d.find("alpha")); // wraps to the first
    try testing.expectEqual(@as(u32, 0), d.selLo());
    try testing.expect(!d.find("gamma"));
}
