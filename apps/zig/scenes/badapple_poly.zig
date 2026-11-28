// --------------------------------------------------------------------------
// BAD APPLE!! POLYGONS (cart 168): the same film as cart 166 as a POLYGON STREAM, STNICCC style (R92,
// docs/ports/badapple/README.md, HINTS.md §5). Offline (tools/badapple/poly_trace.py) each frame's silhouettes
// are traced along the pixel boundaries and simplified (Douglas-Peucker, 0.75 px); a contour that kept its
// vertex count is sent as KEEP or as -7..+7 vertex moves (DELTA) of the last frame's. Each frame the cart fills
// all of POLY.BIN's contours in ONE even-odd scan (badapple/polyfill.zig: holes are just more contours), integer
// only, and repaints the rows whose change points moved. The player (clock, read-ahead, palette, song) is cart
// 166's (badapple/film.zig).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const poly = @import("badapple/poly.zig");
const film = @import("badapple/film.zig");

/// The decoder's ~176 KB of vertex pools and edge tables live in zg.mem, not in the cart's statics (a static that
/// big is a zero-filled data segment: apps/harness/zero_segments.mjs).
const HeapState = struct {
    s: *poly.State,

    pub fn reset(self: *HeapState) void {
        self.s = &zg.mem.mustAlloc(poly.State, 1)[0];
        self.s.reset();
    }

    pub fn beginBlock(self: *HeapState, raw: []const u8) ?usize {
        return self.s.beginBlock(raw);
    }

    pub fn decodeFrame(self: *HeapState, bytes: []const u8, fb: []u8, stride: u16) bool {
        return self.s.decodeFrame(bytes, fb, stride);
    }
};

const Poly = struct {
    pub const MAGIC = poly.MAGIC;
    pub const FILE = "POLY.BIN";
    pub const MAX_PACKED = poly.MAX_PACKED;
    pub const MAX_RAW = poly.MAX_RAW;
    pub const State = HeapState;
};

pub const Demo = film.Film(Poly);
