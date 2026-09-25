// --------------------------------------------------------------------------
// The PO·RNO wobble, $185E (parts 1 and 13).
//
// Every line picks a whole row of the 256x256 one-plane logo through two sine
// walkers, and the row is written into ONE plane of the visible screen — plane
// f & 3. So the four planes hold the logo as it was on frames f, f-1, f-2 and
// f-3, and the popcount-grey palette ($1EE2) shows a pixel black where all four
// had logo, white where none did, and grey in between: the ghost trail is the
// planes, not a blend. Pixels 0..31 and 288..319 are never written and stay
// colour 15.
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const st = @import("st.zig");

const FIRST_ROW: i32 = 0x1C; // d7 starts at 28
const LOGO_X: usize = 0x10; // byte +$10 = pixel 32
const WORDS: usize = 16; // 256 px

/// The row list, written to $6BDE4 as byte offsets (row * 32) and drawn in the
/// same call.
pub fn rows(f: u16, list: *[st.LINES]u16) void {
    var a = A.seedU(f, 27);
    var b = A.seedS(f, -19);
    for (list, 0..) |*out, y| {
        const d4 = (FIRST_ROW + @as(i32, @intCast(y))) * 32 + 2 * (A.sw(a) + A.sw(b));
        out.* = @intCast(d4 & 0x1FE0);
        a = A.step(a, 11);
        b = A.step(b, 9);
    }
}

pub fn draw(scr: *[st.BYTES]u8, f: u16, list: *const [st.LINES]u16) void {
    const plane: usize = (f & 3) * 2;
    for (list, 0..) |off, y| {
        const src = A.porno[off..][0 .. WORDS * 2];
        const dst = scr[y * st.LINE + LOGO_X + plane ..];
        for (0..WORDS) |g| dst[g * 8 ..][0..2].* = src[g * 2 ..][0..2].*;
    }
}
