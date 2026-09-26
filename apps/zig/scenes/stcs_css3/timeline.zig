// --------------------------------------------------------------------------
// The intro's frames, as the program sequences them after its entry:
//   24 black VBLs ($0..$1DC: the pictures decoded under an all-black palette),
//   then from the picture on, frame t:
//     t < 709       the star release ($1F2): one more speed goes live every
//                   ~7.09 frames (a measured busy loop), raster VBL + stars
//     t < 793       the warp ($22A): $E71E = 7 .. 1, 12 frames a step
//     after         the main loop ($AA2)
// --------------------------------------------------------------------------
const Machine = @import("machine.zig").Machine;
const raster = @import("raster.zig");
const scroller = @import("scroller.zig");
const columns = @import("columns.zig");

/// Program entry to the picture ($1DC's Supexec), in VBLs.
pub const PREROLL: u64 = 24;
/// The star release loop ($1F2), measured in Hatari: 100 stars in 709 VBLs.
pub const RELEASE_VBLS: u64 = 709;
/// The warp ($22A): $E71E = 7 .. 1, 12 VBLs each.
pub const WARP_STEP: u64 = 12;
pub const MAIN_LOOP: u64 = RELEASE_VBLS + 7 * WARP_STEP;

/// Frame t of the intro, counted from the picture.
pub fn intro(m: *Machine, t: u64) void {
    if (t < RELEASE_VBLS) {
        const want: usize = @intCast(@min(t * 100 / RELEASE_VBLS + 1, 100));
        while (m.released < want) m.releaseStar();
        startupFrame(m);
    } else if (t < MAIN_LOOP) {
        m.warp = @intCast(7 - (t - RELEASE_VBLS) / WARP_STEP);
        startupFrame(m);
    } else {
        m.warp = 0;
        frame(m);
    }
}

/// Before the main loop only the raster VBL and the stars run.
fn startupFrame(m: *Machine) void {
    raster.vbl(m);
    m.stars();
}

/// raster VBL -> stars -> (music) -> scroller -> main loop: columns, letters.
fn frame(m: *Machine) void {
    raster.vbl(m);
    m.stars();
    scroller.step(m);
    columns.columns(m);
    columns.letters(m);
}
