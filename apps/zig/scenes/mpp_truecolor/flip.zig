// --------------------------------------------------------------------------
// Two pixel buffers a plane, so the next picture is drawn where nothing shows
// (mpp_truecolor/stage.zig) and the switch is one write of the plane's base
// register (REG_FB_BASE): nothing visible changes until that frame, and that
// frame writes no pixel at all. Two planes take turns: plane 0 (8-bit, modes 1
// and 2) and the true-colour plane TC (RGB565, mode 3, HW 1.15.0).
// The spare buffers are VRAM (64,000 + 128,000 B); without room each plane keeps
// one buffer and the pixels go into the shown one, on the switch frame.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blob = @import("blob.zig");

/// The plane mode 3 shows: its own buffers, so plane 0's stay what they are.
pub const TC: usize = 1;

var back8: [*]u8 = undefined;
var back_tc: zg.tc.Fb = undefined;
var have = false;

/// Make plane TC a true-colour window (128,000 B of VRAM, taken first so it always fits).
pub fn setup(os: *zg.ZigOS) void {
    _ = os.lfbs[TC].setTruecolorPlane(.window);
}

/// Take a spare buffer for both planes; false (one buffer each) when VRAM is full.
pub fn install() bool {
    const w = zg.vramWords(blob.W * blob.H / 4) orelse return false;
    back_tc = zg.truecolorBuffer(.window) orelse return false;
    back8 = @ptrCast(w.words.ptr);
    have = true;
    return true;
}

/// Whether the next picture's pixels can be drawn while the current one shows.
pub fn doubled() bool {
    return have;
}

/// Where plane 0's next picture goes: its hidden buffer, or the shown one.
pub fn target(os: *zg.ZigOS) [*]u8 {
    return if (have) back8 else os.lfbs[0].fb;
}

/// Where the true-colour plane's next picture goes.
pub fn targetTc(os: *zg.ZigOS) zg.tc.Fb {
    return if (have) back_tc else zg.tc.view(os.lfbs[TC].fb, .window);
}

/// Show the buffer `target` (or `targetTc`) named: that plane's base register moves to it.
pub fn show(os: *zg.ZigOS, kind: blob.Kind) void {
    if (!have) return;
    if (kind == .rgb565) {
        back_tc = os.lfbs[TC].showTruecolor(back_tc);
        return;
    }
    const fb = &os.lfbs[0];
    const shown = fb.fb;
    fb.fb = back8;
    back8 = shown;
    fb.setScroll(0, 0); // REG_FB_BASE = fb, the buffer's own start
}
