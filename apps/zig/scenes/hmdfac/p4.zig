// --------------------------------------------------------------------------
// Phase 4 ($1119a, every frame) on the machine's own two pages: each kept in
// the ST's planar layout on zg.mem and drawn exactly as the 68000 draws it
// (p4_dots.zig, p4_scroll.zig), each mirrored into its own half of the plane
// buffer write by write (p4_page.zig), and the page just drawn SHOWN by
// moving the plane's read base onto it — the machine's screen-base swap.
// The two halves are 312 rows apart: the opening's bob uses the first.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const A = @import("assets.zig");
const R = @import("rasters.zig");
const dots = @import("p4_dots.zig");
const scroller = @import("p4_scroll.zig");
const P = @import("p4_page.zig");

pub const HALF = zg.PHYSICAL_HEIGHT + 32; // rows a plane-buffer page takes

pub var pages: [2][]u8 = .{ &.{}, &.{} }; // the planar bytes
pub var drawn: u1 = 0; // the page the next frame draws on

pub fn alloc() void {
    for (&pages) |*p| p.* = @as([*]u8, @ptrCast(zg.mem.mustAlloc(u32, P.BYTES / 4).ptr))[0..P.BYTES];
    dots.alloc();
}

fn plate(whole: blit.Dst, k: usize) blit.Dst {
    return whole.window(A.ART_X, k * HALF + A.ART_Y, A.ART_W, A.ART_H);
}

/// $ade0..$1103a: both pages cleared with band B at page row 199 and the
/// laser stripes on their rows, the ring precalculated, the scroller at rest.
pub fn reset(whole: blit.Dst) void {
    whole.fill(0, 0, whole.w, whole.h, 0);
    for (0..2) |k| {
        @memset(pages[k], 0);
        blit.blit(plate(whole, k), blit.Image.init(A.band_b_data, A.ART_W), null, 0, A.BAND_B_Y, null, .copy);
        R.stamp(whole, k * HALF, false);
    }
    dots.reset();
    scroller.reset();
    drawn = 0;
}

/// One frame on the next page, then show it.
pub fn frame(fb: *zg.LogicalFB, whole: blit.Dst) void {
    const page = P.Page{ .planar = pages[drawn].ptr, .plate = plate(whole, drawn).buf.ptr, .stride = whole.stride };
    dots.clearBox(&page);
    scroller.wave();
    scroller.draw(&page);
    dots.plot(&page);
    fb.setScroll(0, @as(u32, drawn) * HALF);
    drawn ^= 1;
}
