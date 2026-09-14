// --------------------------------------------------------------------------
// TNT2 and the hub's return note (union_demo/return_note.zig, kept in the ROM's
// scratch bytes). screen.js inits its scrolltext at jsApp.mainscrollerPos
// (:33, :61) and hands the position back on every update (:91), so the hub's
// scroller carries on from where TNT2's stopped.
//
// Only a note the hub left for TNT2's own door, naming a letter inside the
// text, is believed. Anything else (a cold boot, a note for another door, a ROM
// without scratch) starts the text at 0, and the scratch is never written.
// --------------------------------------------------------------------------
const rom = @import("rom_sdk");
const doors = @import("../union_demo/doors.zig");
const return_note = @import("../union_demo/return_note.zig");

pub const Note = return_note.Note;

/// TNT2's index in the hub's DOORS: the door whose screen is TNT2's.
const OUR_DOOR: usize = blk: {
    for (doors.DOORS, 0..) |d, i| if (d.screen == .tnt2_screen) break :blk i;
    @compileError("no hub door leads to TNT2");
};

/// The hub's note, when it was left for TNT2 and names a letter of a `text_len` text.
pub fn accepted(text_len: usize) ?Note {
    const buf = scratch() orelse return null;
    const n = return_note.peek(buf) orelse return null;
    if (n.door != OUR_DOOR or n.scroll >= text_len) return null;
    return n;
}

/// jsApp.mainscrollerPos = scrolltext.scroffset: the accepted note again, with
/// TNT2's scroller position in place of the hub's.
pub fn handBack(n: Note, scroll: usize) void {
    const buf = scratch() orelse return;
    return_note.write(buf, .{ .door = n.door, .x = n.x, .y = n.y, .scroll = @intCast(scroll) });
}

/// The ROM's scratch bytes (rom_sdk.romScratchPtr), or null on a ROM without
/// them: the page's tolerant env stubs a missing export to 0.
fn scratch() ?[]u8 {
    const len = rom.romScratchLen();
    const ptr = rom.romScratchPtr();
    if (len == 0 or ptr == 0) return null;
    return @as([*]u8, @ptrFromInt(ptr))[0..len];
}
