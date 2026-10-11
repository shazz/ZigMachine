// --------------------------------------------------------------------------
// The bucket ramp under everything, kept in place instead of repainted.
//
// The plane is never cleared between frames (only the PFB is), and the ramp is
// the same pattern on every row, changing only when rasters.count does. So a
// frame needs the ramp back only where LAST frame drew over it: the logo's
// clipped rectangle and the scrolltext's band. Everything else is still the
// ramp it was. Every pixel the blitter writes costs, so all 112,000 of them
// under a logo that covers about 79,000 are repainted only when they must be.
//
// And at count = 1 (ORIGINAL mode's bars, theta = 0) the ramp is ONE index,
// FIRST_BUCKET, on every pixel. So the logo's transparent index is recoded to
// FIRST_BUCKET once at load, and the logo goes down as a plain OPAQUE copy:
// its transparent pixels write exactly the ramp they would have shown. Then
// only the part of last frame's rectangles the new logo does not cover needs
// the ramp, as FILLs (no source to read). With more buckets the ramp varies
// along the row and the logo moves over it, so there the logo stays keyed (on
// FIRST_BUCKET now, the same pixels) over a ramp restored under both old
// rectangles.
//
// ENABLED = false is the previous renderer, kept to compare: the whole ramp
// every frame, the logo keyed on TRANSPARENT and not recoded. Both paths draw
// the same pixels (apps/scene_hash.mjs, every frame through ORIGINAL and ZIG).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const A = @import("assets.zig");
const rasters = @import("rasters.zig");

pub const ENABLED = true;

/// The index the logo is keyed on: TRANSPARENT as depacked, or FIRST_BUCKET
/// once recode() has run (the art ends at 106, so it is free in the logo).
pub const LOGO_KEY: u8 = if (ENABLED) A.FIRST_BUCKET else A.TRANSPARENT;

/// Plane pixels [x0, x1) x [y0, y1).
pub const Rect = struct {
    x0: i32 = 0,
    y0: i32 = 0,
    x1: i32 = 0,
    y1: i32 = 0,

    pub const empty = Rect{};

    pub fn isEmpty(r: Rect) bool {
        return r.x0 >= r.x1 or r.y0 >= r.y1;
    }
};

pub fn recode(logo: []u8) void {
    if (!ENABLED) return;
    for (logo) |*p| {
        if (p.* == A.TRANSPARENT) p.* = A.FIRST_BUCKET;
    }
}

pub const Ramp = struct {
    painted: usize, // the rasters.count the plane's ramp shows; 0 = none yet
    drawn: [2]Rect, // last frame's logo and scrolltext rectangles

    pub fn init(self: *Ramp) void {
        self.painted = 0;
        self.drawn = .{ Rect.empty, Rect.empty };
    }

    /// Put the ramp back wherever the frame about to draw `logo` needs it.
    /// Returns true when the logo may be copied opaque (count = 1).
    pub fn prepare(self: *Ramp, bl: *zg.Blitter, fb: *zg.LogicalFB, logo: Rect) bool {
        const full = Rect{ .x1 = @intCast(fb.fb_w), .y1 = @intCast(fb.fb_h) };
        if (!ENABLED or self.painted != rasters.count) {
            paint(bl, fb, full);
            self.painted = rasters.count;
            return ENABLED and rasters.count == 1;
        }
        if (rasters.count != 1) {
            for (self.drawn) |r| paint(bl, fb, r);
            return false;
        }
        for (self.drawn) |r| {
            var parts: [4]Rect = undefined;
            for (subtract(r, logo, &parts)) |p| fillFirst(bl, fb, p);
        }
        return true;
    }

    pub fn drew(self: *Ramp, logo: Rect, scroll: Rect) void {
        self.drawn = .{ logo, scroll };
    }
};

/// The ramp over `r`: ONE blitter op whose source is rasters.row in cart RAM,
/// read at stride 0 for every row. The plane is never its own source: a
/// plane-to-plane copy (the old "write the first row, double it down") makes
/// CHISEL wait for each write before the next read wherever source and
/// destination spans may overlap, ~31 clocks a pixel on the board, which was
/// 3.5 Mc of a ZIG frame; from cart RAM it streams.
fn paint(bl: *zg.Blitter, fb: *zg.LogicalFB, r: Rect) void {
    if (r.isEmpty()) return;
    const x0: usize = @intCast(r.x0);
    const w: usize = @intCast(r.x1 - r.x0);
    bl.blitRow(fb, @intCast(r.x0), @intCast(r.y0), rasters.row[x0..][0..w], @intCast(r.y1 - r.y0), null);
}

/// The ramp over `r` at count = 1, where every column is FIRST_BUCKET.
fn fillFirst(bl: *zg.Blitter, fb: *zg.LogicalFB, r: Rect) void {
    if (r.isEmpty()) return;
    bl.fill(fb, @intCast(r.x0), @intCast(r.y0), @intCast(r.x1 - r.x0), @intCast(r.y1 - r.y0), A.FIRST_BUCKET);
}

/// `a` minus `b` as up to four disjoint rectangles: the rows above and below
/// `b`, then the columns either side of it in between.
fn subtract(a: Rect, b: Rect, out: *[4]Rect) []Rect {
    if (a.isEmpty()) return out[0..0];
    const i = Rect{ .x0 = @max(a.x0, b.x0), .y0 = @max(a.y0, b.y0), .x1 = @min(a.x1, b.x1), .y1 = @min(a.y1, b.y1) };
    if (i.isEmpty()) {
        out[0] = a;
        return out[0..1];
    }
    out[0] = .{ .x0 = a.x0, .y0 = a.y0, .x1 = a.x1, .y1 = i.y0 };
    out[1] = .{ .x0 = a.x0, .y0 = i.y1, .x1 = a.x1, .y1 = a.y1 };
    out[2] = .{ .x0 = a.x0, .y0 = i.y0, .x1 = i.x0, .y1 = i.y1 };
    out[3] = .{ .x0 = i.x1, .y0 = i.y0, .x1 = a.x1, .y1 = i.y1 };
    return out[0..4];
}
