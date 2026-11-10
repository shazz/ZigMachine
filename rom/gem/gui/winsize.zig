// --------------------------------------------------------------------------
// How big a window may be made (the desktop's and a program's: window.zig's size
// drag, appwin.zig's wind_set WF_CURRXYWH). Two board bugs (9 Nov):
//
//   G22  in low res the sizer let a window grow past the screen. As TOS: a window
//        may be DRAGGED partly off the screen by its mover, never SIZED past the
//        screen's right or bottom edge.
//   G23  sized to its minimum, vertical line artefacts: MIN_H (44) was smaller than
//        the gadgets it must hold, so the vertical track came out with a negative
//        height and the fills cast it to a huge unsigned one. The minimum is now
//        what TOS's is: room for every gadget, the closer / fuller and title, and on
//        each scroll bar both arrows, one cell of track and the sizer.
//
// Sizes are whole 8-px character cells (GEM's), rounded up, except where the
// screen's edge cuts a size short. Pure: native tests (rom/gem/gui_obj_test.zig).
// --------------------------------------------------------------------------
const std = @import("std");
const glyphs = @import("../gem_glyphs.zig");

pub const CELL: i16 = 8;
const GW: i16 = glyphs.GW;
const GH: i16 = glyphs.GH;

/// The harness's mutants (deskSetEngine's bits 27, 28, set by rom_main.zig): the old bugs back.
pub var breaks: u32 = 0;
pub const BREAK_NOCLAMP: u32 = 1 << 27; // G22: a size may pass the screen's edge
pub const BREAK_OLDMIN: u32 = 1 << 28; // G23: the minimum is the window's floor only (MIN_H 44)

pub fn cellsUp(v: i16) i16 {
    return @divTrunc(v + CELL - 1, CELL) * CELL;
}

/// The narrowest a window can be: left and right arrows, a cell of track and the sizer along
/// the bottom (gadgets share their frame lines); `floor` is the window's own (min_w).
pub fn minW(floor: i16) i16 {
    if (breaks & BREAK_OLDMIN != 0) return floor;
    return @max(floor, cellsUp(4 * GW - 3));
}

/// The lowest: the title bar and info line (`top_bars`), then the up arrow, a cell of track,
/// the down arrow and the sizer down the right; `floor` is the window's own (min_h).
pub fn minH(floor: i16, top_bars: i16) i16 {
    if (breaks & BREAK_OLDMIN != 0) return floor;
    return @max(floor, cellsUp(top_bars + 4 * GH - 3));
}

/// A size from a drag (`want`), in cells, no bigger than the `room` up to the screen's edge,
/// never smaller than `min`.
pub fn fit(want: i16, min: i16, room: i16) i16 {
    if (breaks & BREAK_NOCLAMP != 0) return @max(min, cellsUp(want));
    return @max(min, @min(cellsUp(want), room));
}

const expectEqual = std.testing.expectEqual;

test "the minimum holds every gadget with a track of at least one gadget cell" {
    const h = minH(44, 11 + 10); // title + info line, the old MIN_H
    try std.testing.expect(h - (11 + 10) - 3 * GH + 2 >= GH);
    try std.testing.expect(@mod(h, CELL) == 0);
    try std.testing.expect(minW(64) - 3 * GW + 2 >= GW);
    try expectEqual(@as(i16, 200), minW(200)); // a window's own floor wins
}

test "a size never passes the screen's edge, nor goes under the minimum" {
    try expectEqual(@as(i16, 312), fit(400, 64, 312)); // low res: x 8, the edge at 320
    try expectEqual(@as(i16, 64), fit(10, 64, 312));
    try expectEqual(@as(i16, 104), fit(97, 64, 312)); // whole cells, rounded up
    try expectEqual(@as(i16, 64), fit(300, 64, 20)); // a window mostly off the screen: still its minimum
}
