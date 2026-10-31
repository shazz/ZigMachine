// --------------------------------------------------------------------------
// Two pixel buffers a plane, so the next picture is drawn where nothing shows
// (mpp_truecolor/stage.zig) and the switch is one write of each plane's base
// register (REG_FB_BASE, through setScroll(0, 0) on the swapped `fb`): nothing
// visible changes until that frame, and that frame writes no pixel at all.
// The spare buffers are VRAM words (4 x 64,000 B); without room every plane
// keeps one buffer and the pixels go into the shown one, on the switch frame.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blob = @import("blob.zig");

const PLANES = blob.PLANES;
const BYTES = blob.W * blob.H;

var back: [PLANES][*]u8 = undefined;
var have = false;

/// Take a spare buffer for every plane; false (one buffer each) when VRAM is full.
pub fn install() bool {
    var spare: [PLANES][*]u8 = undefined;
    for (&spare) |*b| b.* = @ptrCast((zg.vramWords(BYTES / 4) orelse return false).words.ptr);
    back = spare;
    have = true;
    return true;
}

/// Whether the next picture's pixels can be drawn while the current one shows.
pub fn doubled() bool {
    return have;
}

/// Where plane `p`'s next picture goes: its hidden buffer, or the shown one.
pub fn target(os: *zg.ZigOS, p: usize) [*]u8 {
    return if (have) back[p] else os.lfbs[p].fb;
}

/// Show the buffers `target` named: each plane's base register moves to the other buffer.
pub fn show(os: *zg.ZigOS) void {
    if (!have) return;
    for (&os.lfbs, &back) |*fb, *b| {
        const shown = fb.fb;
        fb.fb = b.*;
        b.* = shown;
        fb.setScroll(0, 0); // REG_FB_BASE = fb, the buffer's own start
    }
}
