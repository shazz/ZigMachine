// --------------------------------------------------------------------------
// P8 greetings logo scroller, 12 px true-colour cells. Kernel $201F4, top
// border open: 67 logo rows x 4 lines, each line 37 x move.w (An)+,(Am) from
// the 672-word row at column S/2, starting at rel D+304+512n.
// D is the delay patched at $2030E: 16, 12 or 8 cycles. After each kernel it
// rotates 16 -> 12 -> 8 -> 16 and every return to 16 moves the column on: a
// steady 4 px a frame leftward scroll from a 12 px cell.
// --------------------------------------------------------------------------
const core = @import("core.zig");
const out = @import("out.zig");
const rip = @import("rip.zig");
const assets = @import("assets.zig");

var S: u32 = 0; // $6090C, bytes, wraps from $4F8 to 0
var trip: [3]u8 = undefined; // the three delay patches at $204C6, in cycles
var cur: u8 = 0; // the delay patched in now

pub fn reset() void {
    S = rip.P8_S;
    trip = rip.P8_TRIP;
    cur = rip.P8_CUR;
}

pub fn init() void {
    core.colour = 0;
}

pub fn vbl() void {
    core.colour = 0;
}

pub fn kernel(l0: u32) void {
    const D: u32 = cur;
    const c0 = S >> 1;
    for (0..268) |ni| {
        const n: u32 = @intCast(ni);
        const o = (n >> 2) * 672 + c0; // at S/2 > 635 the window runs into the next row, as in the demo
        const base = D + 304 + 512 * n;
        for (0..37) |j| out.emit(l0, base + 12 * @as(u32, @intCast(j)), core.le16(assets.p8_logo, o + j));
    }
    out.emit(l0, D + 304 + 512 * 268 + 4, 0);
    core.colour = 0;
    const first = trip[0]; // (not an aggregate literal: it would alias its own result)
    trip[0] = trip[1];
    trip[1] = trip[2];
    trip[2] = first;
    cur = trip[0];
    if (trip[0] == 16) S = if (S >= 0x4F8) 0 else S + 2;
}
