// --------------------------------------------------------------------------
// TC TEST's local pictures: the owner's own files (prototypes/tc_test_art/), converted to
// RGB565 by tools/tc_art.py and embedded ONLY when the cart is built with
// `-Dtc-art=<dir>` (ZM_TC_ART=<dir> ./build.sh --fast). Without it `tc_art` is an empty
// list (build.zig tcArt) and no picture is in the cart: the one docs/ publishes.
// A picture is shown as it is, centred on black: its 565 words are copied, never changed
// (a Falcon dump stays byte-exact), and nothing moves it.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const tc_art = @import("tc_art");
const paint = @import("paint.zig");

pub const count: usize = tc_art.images.len;

/// Say so when the cart carries local pictures: this also keeps the marker string in the
/// cart's data, where apps/tc_test_check.mjs looks for it in the git-tracked cart.
pub fn announce() void {
    if (count > 0) zg.Console.log("tc_test: {d} local picture(s) [{s}]", .{ count, tc_art.marker });
}

/// Picture i, centred in the 400x280 plane buffer (rows are copied as bytes).
pub fn show(fb: zg.tc.Fb, i: usize) void {
    const img = tc_art.images[i];
    fb.fill(0);
    const x0 = (paint.W - img.w) / 2;
    const y0 = (paint.H - img.h) / 2;
    const row_bytes = @as(usize, img.w) * 2;
    for (0..img.h) |y| {
        const dst: [*]u8 = @ptrCast(fb.row(y0 + y)[x0..].ptr);
        @memcpy(dst[0..row_bytes], img.px[y * row_bytes ..][0..row_bytes]);
    }
}
