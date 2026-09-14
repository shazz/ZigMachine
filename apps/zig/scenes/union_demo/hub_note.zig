// --------------------------------------------------------------------------
// jsApp.mainscrollerPos between the Union Demo hub and a door screen, carried in
// the hub's "UNI1" note (return_note.zig) in the ROM's scratch bytes.
//
// The remake's screens that start their scroller at jsApp.mainscrollerPos also
// store their own position back into it (0.9.8: tnt1 screen.js:74, tnt2 :91,
// superscroller :84, reps :179, L16 :89, beatdis screen.js:85 / screen2.js:116),
// where the menu's scroller resumes (main.js:467). A cart swap replaces the
// whole cart, so here a screen peeks at the note when it starts and, when it
// leaves for the hub, writes it back with the hub's door and Charly's x/y
// untouched and its own scroll. The hub take()s it on return.
//
// HubNote(tag) is that for the screen the door launching the demo-<tag> cart
// leads to. Only a note naming that door is believed (a note for another door is
// not this launch's); accepted() also wants the scroll inside the text. WHEN a
// screen reads and writes stays with the screen: each port keeps its remake's
// timing (read at init or at the start of the run, write only after a run).
//
// The *In functions work on a plain byte slice and test natively
// (apps/zig/scene_tests.zig); only scratch() reaches the ROM.
// --------------------------------------------------------------------------
const std = @import("std");
const return_note = @import("return_note.zig");
const doors = @import("doors.zig");

pub fn HubNote(comptime tag: []const u8) type {
    return struct {
        pub const Note = return_note.Note;

        /// This screen's index in doors.DOORS: what the hub's note names as its door.
        pub const DOOR: usize = blk: {
            for (doors.DOORS, 0..) |d, i| if (d.tag) |t| if (std.mem.eql(u8, t, tag)) break :blk i;
            @compileError("no Union Demo door launches " ++ tag);
        };

        /// The hub's note when it was left for this door, whatever its scroll;
        /// null on a ROM without scratch bytes, with no note, or another door's.
        pub fn mine() ?Note {
            return mineIn(scratch() orelse return null);
        }

        /// The hub's note when it was left for this door with a scroll inside a
        /// `text_len` text; null otherwise, and the scroller starts at 0.
        pub fn accepted(text_len: usize) ?Note {
            return acceptedIn(scratch() orelse return null, text_len);
        }

        /// jsApp.mainscrollerPos = scroffset, for the hub to resume at: `n` as
        /// read, its scroll replaced by this screen's `scroll`.
        pub fn handBack(n: Note, scroll: usize) void {
            handBackIn(scratch() orelse return, n, scroll);
        }

        /// mine() on `buf`: peeked, so the note is not spent.
        pub fn mineIn(buf: []const u8) ?Note {
            const n = return_note.peek(buf) orelse return null;
            return if (n.door == DOOR) n else null;
        }

        pub fn acceptedIn(buf: []const u8, text_len: usize) ?Note {
            const n = mineIn(buf) orelse return null;
            return if (n.scroll < text_len) n else null;
        }

        pub fn handBackIn(buf: []u8, n: Note, scroll: usize) void {
            return_note.write(buf, .{ .door = n.door, .x = n.x, .y = n.y, .scroll = @intCast(scroll) });
        }
    };
}

/// The ROM's scratch bytes (rom_sdk.romScratchPtr), or null on a ROM without
/// them: the page's tolerant env stubs a missing export to return 0. rom_sdk is
/// imported here, not at file scope, so the native tests never reach it.
pub fn scratch() ?[]u8 {
    const rom = @import("rom_sdk");
    const len = rom.romScratchLen();
    const ptr = rom.romScratchPtr();
    if (len == 0 or ptr == 0) return null;
    return @as([*]u8, @ptrFromInt(ptr))[0..len];
}

const expectEqual = std.testing.expectEqual;
const L16 = HubNote("union_l16");
const TNT1 = HubNote("union_tnt1");
const TNT2 = HubNote("union_tnt2");

test "the door is found by tag, as the screen id finds it" {
    try expectEqual(doors.DOORS[L16.DOOR].screen, .l16_screen);
    try expectEqual(doors.DOORS[TNT1.DOOR].screen, .tnt1_screen);
    try expectEqual(doors.DOORS[TNT2.DOOR].screen, .tnt2_screen);
    // the first such door, as TNT1's and TNT2's own screen-id searches found it
    for (doors.DOORS[0..TNT1.DOOR]) |d| try std.testing.expect(d.screen != .tnt1_screen);
    for (doors.DOORS[0..TNT2.DOOR]) |d| try std.testing.expect(d.screen != .tnt2_screen);
}

test "a note for the screen's own door is accepted" {
    var buf = [_]u8{0} ** 64;
    return_note.write(&buf, .{ .door = @intCast(L16.DOOR), .x = 1500, .y = 127, .scroll = 212 });
    const n = L16.acceptedIn(&buf, 213) orelse return error.TestExpectedNote;
    try expectEqual(@as(u32, 212), n.scroll);
}

test "a note for another door is refused" {
    var buf = [_]u8{0} ** 64;
    return_note.write(&buf, .{ .door = @intCast(TNT2.DOOR), .x = 1500, .y = 127, .scroll = 12 });
    try expectEqual(@as(?return_note.Note, null), L16.acceptedIn(&buf, 1000));
    try expectEqual(@as(?return_note.Note, null), L16.mineIn(&buf));
}

test "a scroll outside the text is refused, but the note is still the door's" {
    var buf = [_]u8{0} ** 64;
    return_note.write(&buf, .{ .door = @intCast(L16.DOOR), .x = 1500, .y = 127, .scroll = 212 });
    try expectEqual(@as(?return_note.Note, null), L16.acceptedIn(&buf, 212));
    try expectEqual(@as(u32, 212), (L16.mineIn(&buf) orelse return error.TestExpectedNote).scroll);
}

test "handBack keeps door, x and y and puts in the screen's scroll" {
    var buf = [_]u8{0} ** 64;
    return_note.write(&buf, .{ .door = @intCast(TNT2.DOOR), .x = 4236.5, .y = 127, .scroll = 57 });
    const n = TNT2.acceptedIn(&buf, 100) orelse return error.TestExpectedNote;
    TNT2.handBackIn(&buf, n, 901);
    const back = return_note.take(&buf) orelse return error.TestExpectedNote;
    try expectEqual(@as(u8, @intCast(TNT2.DOOR)), back.door);
    try expectEqual(@as(f32, 4236.5), back.x);
    try expectEqual(@as(f32, 127), back.y);
    try expectEqual(@as(u32, 901), back.scroll);
}

test "reading the note does not spend it" {
    var buf = [_]u8{0} ** 64;
    return_note.write(&buf, .{ .door = @intCast(L16.DOOR), .x = 686, .y = 127, .scroll = 3 });
    _ = L16.acceptedIn(&buf, 10) orelse return error.TestExpectedNote;
    _ = L16.mineIn(&buf) orelse return error.TestExpectedNote;
    try expectEqual(@as(u32, 3), (return_note.take(&buf) orelse return error.TestExpectedNote).scroll);
}
