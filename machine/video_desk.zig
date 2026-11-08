// --------------------------------------------------------------------------
// The desk mode (HW 1.17.0, RESOLUTION = RES_DESK, docs/GEM_DESK_MODE.md): plane 0
// alone, 640x480 palette indices at stride 640 from FB_BASE[0] & ~7, through
// palette 0, shown 1:1. Nothing is composited: no other plane, no HBL handler,
// no copper, no BEAM, no border. The picture is a pure function of plane 0's
// bytes and palette 0, and this file is that function.
//
// A whole 640x480 RGBA picture (1,228,800 B) does not fit in the PFB (896,000 B),
// so the host takes it in two halves: hwRenderDesk(h) writes rows 240h..240h+239
// into the PFB's first 614,400 bytes. On the board the scanout reads plane 0 and
// looks the bytes up in a mirror of palette 0 (fpga/rtl/video/zm_video_scan.v);
// its testbench compares the wire with these halves.
// --------------------------------------------------------------------------
const memmap = @import("sdk/memmap.zig");

pub const W: usize = memmap.DESK_WIDTH; // 640
pub const H: usize = memmap.DESK_HEIGHT; // 480
pub const HALF_ROWS: usize = H / 2; // 240
pub const HALF_PIXELS: usize = W * HALF_ROWS; // 153,600 RGBA words

comptime {
    if (HALF_PIXELS * 4 > memmap.PFB_BYTES) @compileError("video_desk: half a desk picture must fit in the PFB");
}

/// RESOLUTION says desk: clear() only counts the frame, renderPlane() draws nothing.
pub fn active(resolution: u8) bool {
    return resolution == memmap.RES_DESK;
}

/// Plane 0's first byte: a beat (8 bytes) on the board, so bit 0..2 of FB_BASE are ignored.
pub fn baseOf(fb_base: u32) usize {
    return fb_base & ~@as(u32, 7);
}

/// A palette word on the wire: R, G and B as stored (RGBA little-endian), alpha 255 (the mode
/// ignores alpha: the board's mirror keeps only {B, G, R}).
pub inline fn colour(pal_word: u32) u32 {
    return pal_word | 0xFF00_0000;
}

/// Half `half` (0 = rows 0..239, 1 = rows 240..479) of the desk picture into `out`, row-major,
/// 640 words a row. `region` is the video region (offset 0 = HW_VIDEO_BASE), `fb_base` is
/// FB_BASE[0] (a region offset), `palette` palette 0.
pub fn renderHalf(out: [*]u32, region: [*]const u8, fb_base: u32, palette: [*]const u32, half: u32) void {
    const base = baseOf(fb_base);
    const y0: usize = @as(usize, half & 1) * HALF_ROWS;
    var y: usize = 0;
    while (y < HALF_ROWS) : (y += 1) {
        const src = region + base + (y0 + y) * W;
        const row = out + y * W;
        var x: usize = 0;
        while (x < W) : (x += 1) row[x] = colour(palette[src[x]]);
    }
}
