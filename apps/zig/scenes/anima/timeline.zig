// --------------------------------------------------------------------------
// The timeline, in 60 Hz ticks (one board frame each). Every part derives its
// state from the tick (multiplied, never accumulated), so a frame is a pure
// function of it: the harness can jump anywhere and the hashes hold.
//
// OLDSCHOOL (an ST screen, kept ST-honest)
//   0     DARK     borders closed; the copper wakes as one line and splits
//   90    OPEN     the sides open line by line, then the top and bottom
//   210   BREATHE  the ANIMA logo inhales
//   330   SCROLL   stars and the sine scroller
//   480   GLENZ    a cube, then an octahedron
// THE GAG
//   1680  the timing slips: rasters scramble, the borders fill with noise, the
//         screen freezes; a terminal types "THE KESTREL CAN DO MORE THAN THAT"
// NEWSCHOOL (what an ST could not do, 60 fps on the board)
//   2040  TUNNEL   a full-overscan textured tunnel, the camera wandering
//   3000  ROTO     the ANIMA tile rotozoomed and melted, a palette per line
//   3960  TORUS    a lit FPU torus knot in a raster sky
//   4920  END      the ending card
//   6120  the demo starts over
// --------------------------------------------------------------------------
pub const OPEN: u32 = 90;
pub const SIDES_TICKS: u32 = 60; // sides: the middle line to all 200
pub const BANDS_TICKS: u32 = 60; // then top and bottom
pub const BREATHE: u32 = 210;
pub const BREATHE_TICKS: u32 = 90;
pub const SCROLL: u32 = 330;
pub const GLENZ: u32 = 480;
pub const OBJECT_TICKS: u32 = 600; // 10 s an object
pub const ZOOM_TICKS: u32 = 60; // in at the start, out at the end

pub const GAG: u32 = GLENZ + 2 * OBJECT_TICKS; // 1680
pub const TUNNEL: u32 = GAG + 360;
pub const ROTO: u32 = TUNNEL + 960;
pub const TORUS: u32 = ROTO + 960;
pub const END: u32 = TORUS + 960;
pub const LOOP: u32 = END + 1200;

pub const Phase = enum(u8) { dark, open, breathe, scroll, glenz, gag, tunnel, roto, torus, end };

pub fn phase(t: u32) Phase {
    if (t < OPEN) return .dark;
    if (t < BREATHE) return .open;
    if (t < SCROLL) return .breathe;
    if (t < GLENZ) return .scroll;
    if (t < GAG) return .glenz;
    if (t < TUNNEL) return .gag;
    if (t < ROTO) return .tunnel;
    if (t < TORUS) return .roto;
    if (t < END) return .torus;
    return .end;
}

pub const Part = enum(u8) { old, gag, tunnel, roto, torus, end };

pub fn part(t: u32) Part {
    return switch (phase(t)) {
        .dark, .open, .breathe, .scroll, .glenz => .old,
        .gag => .gag,
        .tunnel => .tunnel,
        .roto => .roto,
        .torus => .torus,
        .end => .end,
    };
}

pub fn partStart(p: Part) u32 {
    return switch (p) {
        .old => 0,
        .gag => GAG,
        .tunnel => TUNNEL,
        .roto => ROTO,
        .torus => TORUS,
        .end => END,
    };
}

/// 0..256 over [start, start+len): how far a ramp has run at tick t.
pub fn ramp(t: u32, start: u32, len: u32) u32 {
    if (t <= start) return 0;
    if (t >= start + len) return 256;
    return (t - start) * 256 / len;
}
