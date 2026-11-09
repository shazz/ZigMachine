// --------------------------------------------------------------------------
// Two buffers in the desk mode (Matt on the board, 8 Nov 2026: the screen blinked every time the
// mouse moved). The board's desk scanout reads plane 0 LIVE from cart RAM, and every drawn frame
// of the desktop repaints the whole screen (fill, icons, windows: deskdraw.drawScene), so the
// half-drawn frame was on the screen while the ROM drew it. The browser shows only finished
// frames and never saw it (docs/GEM_DESK_MODE.md §3).
//
// So in the desk the shell hands the ROM two buffers (deskSetBuffers); a frame the desktop draws
// goes into the one NOT on screen, and FB_BASE moves to it once the frame is complete. The board
// latches FB_BASE at the VBL (zm_video_desk.v), and its firmware starts the next frame only after
// that VBL (fpga/cycles/bdesk.c), so the buffer drawn next is never the one being scanned. A frame
// deskdirty skips draws nothing and flips nothing: the screen keeps the last frame. Each drawn
// frame is whole (immediate mode), so the back buffer holding the frame before last is harmless.
//
// The front is read from FB_BASE each frame, not remembered: whatever moved it (the shell's
// setDeskPlane on entry binds the first) is the truth. A FB_BASE that is neither buffer (a pair
// never handed, or another binding) draws in place, as the single-buffered desk did.
// --------------------------------------------------------------------------
const std = @import("std");

/// The two desk buffers, as region offsets; 0 = none handed (draw in place).
pub const Pair = struct {
    a: u32 = 0,
    b: u32 = 0,

    /// The buffer to draw the next frame into when `front` is on screen, null to draw in place.
    pub fn backOf(self: Pair, front: u32) ?u32 {
        if (self.a == 0 or self.b == 0 or self.a == self.b) return null;
        if (front == self.a) return self.b;
        if (front == self.b) return self.a;
        return null;
    }
};

/// Where this frame draws: the back buffer, or the front itself.
pub fn target(p: Pair, front: u32) u32 {
    return p.backOf(front) orelse front;
}

/// FB_BASE after the frame: the frame drawn into the back is shown; a clean frame, or one drawn
/// in place, leaves it.
pub fn after(p: Pair, front: u32, drew: bool) u32 {
    if (!drew) return front;
    return p.backOf(front) orelse front;
}

const expectEqual = std.testing.expectEqual;
const A: u32 = 0x1100;
const B: u32 = 0x1100 + 640 * 480;

test "a drawn frame goes into the buffer not on screen, then becomes the front" {
    const p: Pair = .{ .a = A, .b = B };
    try expectEqual(B, target(p, A));
    try expectEqual(B, after(p, A, true));
    try expectEqual(A, target(p, B)); // and back: the two alternate
    try expectEqual(A, after(p, B, true));
}

test "a clean frame flips nothing" {
    const p: Pair = .{ .a = A, .b = B };
    try expectEqual(A, after(p, A, false));
    try expectEqual(B, after(p, B, false));
}

test "no pair, half a pair, or a front outside it: draw in place, no flip" {
    try expectEqual(A, target(.{}, A));
    try expectEqual(A, after(.{}, A, true));
    try expectEqual(A, after(.{ .a = A }, A, true));
    try expectEqual(A, after(.{ .a = A, .b = A }, A, true));
    const elsewhere: u32 = 0x9000;
    try expectEqual(elsewhere, target(.{ .a = A, .b = B }, elsewhere));
    try expectEqual(elsewhere, after(.{ .a = A, .b = B }, elsewhere, true));
}
