// --------------------------------------------------------------------------
// Repaint only when something changed (KOS on the board, 4 Nov 2026). The desktop is drawn
// immediate-mode: every frame it filled the whole work area and redrew every icon and every open
// window with its directory, which cost ZIGGY ~0.3 Mc a frame idle and ~1.1 Mc with one C:
// window open (apps/frame_cost.mjs): the board fell to ~25 fps as soon as a drive window opened.
//
// Nothing on the desktop moves by itself except the zoom-box, and the plane's logical buffer
// keeps its pixels from frame to frame (hwClear clears the physical picture, not the plane), so
// a frame whose inputs are the last frame's can be skipped whole: same state, same pixels. Every
// way in is a touch(): the pointer moving or a button changing, a double-click, a key, an arrow,
// drive A's disk or C:'s changing, a drive model written, the screen re-bound. After a touch the
// desktop draws SETTLE more frames (what one frame decides, a press selecting an icon, shows on
// the next); it always draws while something is in motion (a button held: drags, the scroll
// arrows; the zoom-box; an open or a launch pending), and SETTLE frames after it stops. Pixel-exact by construction: the skipped
// frames would have drawn the bytes already there (fpga/tests/test_kos_desk_redraw.py holds it).
// --------------------------------------------------------------------------
const dt = @import("desktop.zig");
const Desktop = dt.Desktop;

/// Frames drawn after the last touch before the desktop may rest.
pub const SETTLE: u8 = 2;

pub const State = struct {
    settled: u8 = 0, // frames drawn since the last touch (0: draw)
    drive_word: u32 = 0, // insertDisk's last word (desk_icons.setDrive): only a change touches
};

/// Something the next frame must show changed.
pub fn touch(d: *Desktop) void {
    d.dirty.settled = 0;
}

/// The frame must run: a touch not yet settled, or something in motion.
pub fn mustDraw(d: *const Desktop) bool {
    return d.dirty.settled < SETTLE or moving(d);
}

/// A frame was drawn. A frame in motion counts as a touch: the frames after the motion ends
/// still draw (the zoom-box's last frame leaves its frame on the plane; the next one erases it).
pub fn drew(d: *Desktop) void {
    if (moving(d)) d.dirty.settled = 0 else if (d.dirty.settled < SETTLE) d.dirty.settled += 1;
}

fn moving(d: *const Desktop) bool {
    return d.g.down or d.grow_t != 0 or d.pending_open >= 0 or d.launch_req or d.drag != null or
        d.file_drag >= 0 or d.band or d.wm.drag != null or d.wm.resize != null;
}
