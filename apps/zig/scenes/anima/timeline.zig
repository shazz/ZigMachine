// --------------------------------------------------------------------------
// The timeline, in 60 Hz ticks (one board frame each). Every part reads the
// tick and derives its state from it, so a frame is a pure function of the
// tick: the harness can jump anywhere and the hashes are deterministic.
//
//   0     DARK     borders closed; the copper wakes as one line in the middle
//                  and splits into the bars
//   90    OPEN     the sides open line by line from the middle out, then the
//                  top and bottom borders drop open (flickerBorder per line)
//   210   BREATHE  the ANIMA logo inhales from a line to its full height
//   330   SCROLL   the stars come up and the scroller enters from the right
//   480   GLENZ    the glenz objects: one every OBJECT_TICKS, zooming in and out
// --------------------------------------------------------------------------
pub const OPEN: u32 = 90;
pub const SIDES_TICKS: u32 = 60; // sides: the middle line to all 200
pub const BANDS_TICKS: u32 = 60; // then top and bottom
pub const BREATHE: u32 = 210;
pub const BREATHE_TICKS: u32 = 90;
pub const SCROLL: u32 = 330;
pub const GLENZ: u32 = 480;
pub const OBJECT_TICKS: u32 = 720; // 12 s an object
pub const ZOOM_TICKS: u32 = 60; // in at the start, out at the end

pub const Phase = enum(u8) { dark, open, breathe, scroll, glenz };

pub fn phase(t: u32) Phase {
    if (t < OPEN) return .dark;
    if (t < BREATHE) return .open;
    if (t < SCROLL) return .breathe;
    if (t < GLENZ) return .scroll;
    return .glenz;
}

/// 0..256 over [start, start+len): how far a ramp has run at tick t.
pub fn ramp(t: u32, start: u32, len: u32) u32 {
    if (t <= start) return 0;
    if (t >= start + len) return 256;
    return (t - start) * 256 / len;
}
