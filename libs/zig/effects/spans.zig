// --------------------------------------------------------------------------
// Spans: a sparse overlay image as comptime runs of ink.
//
// A logo that is mostly transparent costs a per-pixel key test on every pixel
// of its box, every frame. Walked once at compile time into horizontal runs of
// non-key pixels, the frame loop becomes a few copies or drawScanline calls per
// row (replicants_dd2: 4942 ink pixels of 64000 → ~500 runs). Two ports
// hand-wrote the two passes (count, then fill) this builds.
//
// Runs never cross a row, and rows keep their own index, so a scene can draw
// the whole image or only a window of rows (replicants_garfield's sliding
// window). All of it is comptime data: nothing is computed on the machine.
//
// No ZigOS import: it tests natively (spans_test.zig).
// --------------------------------------------------------------------------

/// Pixels x0..x1-1 of one row are ink (end-exclusive, like drawScanline).
pub const Span = struct { x0: u16, x1: u16 };

pub fn Runs(comptime n: usize, comptime rows: usize) type {
    return struct {
        const Self = @This();

        w: usize,
        spans: [n]Span,
        /// Row y's runs are spans[row_first[y]..row_first[y + 1]].
        row_first: [rows + 1]u32,

        pub const height = rows;

        /// Row y's runs; a row past the image has none.
        pub fn row(self: *const Self, y: usize) []const Span {
            if (y >= rows) return &.{};
            return self.spans[self.row_first[y]..self.row_first[y + 1]];
        }
    };
}

/// The runs of pixels != `key` in `img`, `w` pixels per row. Always evaluated
/// at compile time, even when called inside a function. The walk is compile
/// time too: a 400x280 overlay adds tens of seconds to a cold build, so for
/// much larger images generate the table with a tool instead.
pub inline fn build(comptime img: []const u8, comptime w: usize, comptime key: u8) Runs(count(img, w, key), img.len / w) {
    return comptime make(img, w, key);
}

fn make(comptime img: []const u8, comptime w: usize, comptime key: u8) Runs(count(img, w, key), img.len / w) {
    @setEvalBranchQuota(4 * img.len + 1000);
    const h = img.len / w;
    var out: Runs(count(img, w, key), h) = undefined;
    out.w = w;
    var n: usize = 0;
    for (0..h) |y| {
        out.row_first[y] = @intCast(n);
        const r = img[y * w ..][0..w];
        var x: usize = 0;
        while (x < w) {
            if (r[x] == key) {
                x += 1;
                continue;
            }
            const start = x;
            while (x < w and r[x] != key) x += 1;
            out.spans[n] = .{ .x0 = @intCast(start), .x1 = @intCast(x) };
            n += 1;
        }
    }
    out.row_first[h] = @intCast(n);
    return out;
}

/// How many runs `build` will produce; it sizes the array exactly.
pub fn count(comptime img: []const u8, comptime w: usize, comptime key: u8) usize {
    if (w == 0) @compileError("spans: zero width");
    if (img.len % w != 0) @compileError("spans: image length is not a multiple of its width");
    if (w > 0xFFFF) @compileError("spans: rows wider than 65535 pixels");
    @setEvalBranchQuota(2 * img.len + 1000);
    var n: usize = 0;
    for (img, 0..) |px, i| {
        if (px != key and (i % w == 0 or img[i - 1] == key)) n += 1;
    }
    return n;
}
