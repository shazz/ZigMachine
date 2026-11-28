// --------------------------------------------------------------------------
// BAD APPLE!! POLYGONS (cart 168): the same film as cart 166 as a POLYGON STREAM, STNICCC style (R92,
// docs/ports/badapple/README.md, HINTS.md §5). Offline (tools/badapple/poly_trace.py) each frame's silhouettes
// are traced along the pixel boundaries and simplified (Douglas-Peucker, 0.75 px); a contour that kept its
// vertex count is sent as KEEP or as -7..+7 vertex moves (DELTA) of the last frame's. Each frame the cart fills
// all of POLY.BIN's contours in ONE even-odd scan (badapple/polyfill.zig: holes are just more contours), integer
// only, and repaints the rows whose change points moved. The player (clock, read-ahead, palette, song) is cart
// 166's (badapple/film.zig).
// --------------------------------------------------------------------------
const poly = @import("badapple/poly.zig");
const film = @import("badapple/film.zig");

const Poly = struct {
    pub const MAGIC = poly.MAGIC;
    pub const FILE = "POLY.BIN";
    pub const MAX_PACKED = poly.MAX_PACKED;
    pub const MAX_RAW = poly.MAX_RAW;
    pub const State = poly.State;
};

pub const Demo = film.Film(Poly);
