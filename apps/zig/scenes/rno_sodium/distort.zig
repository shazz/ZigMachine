// --------------------------------------------------------------------------
// The sine distorter on picture #0, $17BE (part 9).
//
// Whole-row picks only: no x shift and no +y term, so every line of the strip
// is the picture row the two walkers add up to, wrapped mod 256. That wrap
// (and.w #$FF of a sum that runs -512..512) is what folds the lips back on
// themselves. The rows go to the shared list as row * 96 — which is why the
// curtain's first frame of part 10 reads them (curtain.zig).
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const st = @import("st.zig");

/// One frame into `scr` (the back buffer the flip just handed over).
pub fn frame(scr: *[st.BYTES]u8, f: u16, list: *[st.LINES]u16) void {
    var a = A.seedU(f, 7);
    var b = A.seedS(f, -9);
    for (list) |*out| {
        const row: u32 = @as(u32, @bitCast(A.sw(a) + A.sw(b))) & 0xFF;
        out.* = @intCast(row * A.PIC0_ROW);
        a = A.step(a, 6);
        b = A.step(b, 3);
    }
    for (list, 0..) |off, y| {
        @memcpy(scr[y * st.LINE + st.STRIP ..][0..st.STRIP_BYTES], A.pic0[off..][0..A.PIC0_ROW]);
    }
}
