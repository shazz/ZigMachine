// --------------------------------------------------------------------------
// jsApp.mainscrollerPos between the Union Demo hub and this screen, carried in
// the hub's "UNI1" note (union_demo/return_note.zig) in the ROM's scratch bytes.
//
// The remake shares one global: BEAT DIS starts its scroller at it
// (screen.js:39,61, screen2.js:51,93) and stores its own position back into it
// on every update (screen.js:85, screen2.js:116), where the menu's scroller
// resumes (main.js:467). So: peek at the note when the screen starts, and when
// it leaves for the hub put this scroller's position back in the note, with
// the hub's door and Charly's x/y untouched. The hub take()s it on return.
//
// `scroll` is the index of the next character to enter a scroller in
// jsApp.scrolltext, which is the same text in both carts (checked below).
// --------------------------------------------------------------------------
const std = @import("std");
const rom = @import("rom_sdk");
const return_note = @import("../union_demo/return_note.zig");
const doors = @import("../union_demo/doors.zig");
const hub_assets = @import("../union_demo/assets.zig");
const TEXT = @import("screen.zig").TEXT;

pub const Note = return_note.Note;

/// This screen's door, found by its tag in the hub's door table.
const MY_DOOR: u8 = blk: {
    for (doors.DOORS, 0..) |d, i| {
        if (d.tag) |tag| if (std.mem.eql(u8, tag, "union_beatdis")) break :blk i;
    }
    @compileError("no door launches union_beatdis");
};

comptime {
    // The hub's scrolltext.txt is the last part of menu_assets.bin (union_demo/assets.zig).
    const blob = @embedFile("../../assets/screens/union_demo/menu_assets.bin");
    if (blob.len != hub_assets.BLOB_LEN) @compileError("menu_assets.bin is not the layout union_demo/assets.zig reads");
    @setEvalBranchQuota(4 * TEXT.len + 1000);
    if (!std.mem.eql(u8, blob[blob.len - TEXT.len ..], TEXT))
        @compileError("scrolltext.txt differs from the hub's: the note's scroll offset would not index this text");
}

/// The hub's note when it was left for this door with a scroll inside the text;
/// null otherwise, and the scroller starts at 0 (jsApp.mainscrollerPos before
/// any scroller has run).
pub fn peek() ?Note {
    const buf = scratch() orelse return null; // a ROM without scratch bytes
    const note = return_note.peek(buf) orelse return null; // not launched from the hub's door
    if (note.door != MY_DOOR) return null; // a note left for another door's screen
    if (note.scroll >= TEXT.len) return null; // not a position in the text
    return note;
}

/// jsApp.mainscrollerPos = scroffset, for the hub to resume at: `note` as
/// peeked, its scroll replaced by this screen's `scroll`.
pub fn leave(note: Note, scroll: usize) void {
    const buf = scratch() orelse return;
    return_note.write(buf, .{ .door = note.door, .x = note.x, .y = note.y, .scroll = @intCast(scroll) });
}

fn scratch() ?[]u8 {
    const len = rom.romScratchLen();
    const ptr = rom.romScratchPtr();
    if (len == 0 or ptr == 0) return null;
    return @as([*]u8, @ptrFromInt(ptr))[0..len];
}
