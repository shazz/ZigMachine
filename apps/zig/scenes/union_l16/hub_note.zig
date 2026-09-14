// --------------------------------------------------------------------------
// LEVEL 16 and jsApp.mainscrollerPos, the hub scroller's next character, which
// the hub leaves in the ROM scratch when a door launches a screen
// (union_demo/return_note.zig).
//
// screen.js reads it at init (scrolltext.init(..., jsApp.mainscrollerPos), :31
// and :70) and writes its own scroffset back every frame (:89), so the menu
// resumes from L16's text. Here: read the note with peek() at init, and rewrite
// it on the way out, keeping the hub's door and Charly's position.
// --------------------------------------------------------------------------
const std = @import("std");
const rom = @import("rom_sdk");
const return_note = @import("../union_demo/return_note.zig");
const doors = @import("../union_demo/doors.zig");

pub const Note = return_note.Note;

/// This screen's door in the hub, which a note about this launch names.
const MY_DOOR: usize = blk: {
    for (doors.DOORS, 0..) |d, i| if (d.tag) |t| if (std.mem.eql(u8, t, "union_l16")) break :blk i;
    @compileError("no door launches union_l16");
};

fn scratch() ?[]u8 {
    const len = rom.romScratchLen();
    const ptr = rom.romScratchPtr();
    if (len == 0 or ptr == 0) return null; // a ROM without scratch bytes
    return @as([*]u8, @ptrFromInt(ptr))[0..len];
}

/// The hub's note about this launch, left in place; null when there is none, or
/// it names another door (it is not about this launch).
pub fn find() ?Note {
    const buf = scratch() orelse return null;
    const note = return_note.peek(buf) orelse return null;
    if (note.door != MY_DOOR) return null;
    return note;
}

/// Where the text starts: the note's character, or 0 without a note or when it
/// is not a character of this text.
pub fn startOffset(note: ?Note, text_len: usize) usize {
    const n = note orelse return 0;
    return if (n.scroll < text_len) n.scroll else 0;
}

/// jsApp.mainscrollerPos = scrolltext.scroffset, on the way back to the hub.
/// Only a note this launch found is rewritten: without one, nothing is written.
pub fn writeBack(note: ?Note, scroll: usize) void {
    const n = note orelse return;
    const buf = scratch() orelse return;
    return_note.write(buf, .{ .door = n.door, .x = n.x, .y = n.y, .scroll = @intCast(scroll) });
}
