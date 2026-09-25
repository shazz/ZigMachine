// --------------------------------------------------------------------------
// The transitions between parts. Both copy the BACK buffer to the front one
// field at a time, one call per VBL:
//   $D472 / $D570  vertical zoom in / out: the picture squashed into a band of
//                  2n lines about line 100, black above and below
//   $BC62          part 6's curtain: line 2n top-down and 199-2n bottom-up
// --------------------------------------------------------------------------
const st = @import("st.zig");
const Screen = st.Screen;

pub const BLACK: u8 = 0xFF; // "line $7D00": back + 32000, the zeroed gap after the buffer
pub const STEPS_DONE: u16 = 0x68; // callers loop until $144A4 >= $68: 52 calls

/// $D472 builds the table from n = min($144A4, 100).
pub fn zoomInN(step: u16) u16 {
    return @min(step, 100);
}

/// $D570: n = max(100 - $144A4, 0), a signed word compare.
pub fn zoomOutN(step: u16) u16 {
    return @intCast(@max(100 - @as(i32, step), 0));
}

/// The $6F41A line table: 200 source lines, or BLACK. Step 200/(2n) in 16.16
/// from a `divu.w`, the integer part `and`ed to a byte.
pub fn zoomTable(n: u16, table: *[200]u8) void {
    @memset(table, BLACK);
    if (n == 0) return;
    const step: u32 = ((0xC800 / (2 * @as(u32, n))) & 0xFFFF) << 8;
    var acc: u32 = 0;
    for (0..2 * @as(usize, n)) |i| {
        table[100 - n + i] = @truncate(acc >> 16);
        acc +%= step;
    }
}

/// The copy half (after the VBL wait): lines 2i + parity, i = 0..99.
pub fn zoomCopy(front: *Screen, back: *const Screen, table: *const [200]u8, parity: u1) void {
    var line: usize = parity;
    while (line < 200) : (line += 2) {
        const dst = front[line * st.LINE ..][0..st.LINE];
        const src = table[line];
        if (src == BLACK) @memset(dst, 0) else @memcpy(dst, back[@as(usize, src) * st.LINE ..][0..st.LINE]);
    }
}

/// $BC6E: part 6's curtain, step n: back lines 2n and 199-2n onto the front.
pub fn curtainCopy(front: *Screen, back: *const Screen, n: u16) void {
    for ([_]usize{ 2 * @as(usize, n), 199 - 2 * @as(usize, n) }) |y| {
        @memcpy(front[y * st.LINE ..][0..st.LINE], back[y * st.LINE ..][0..st.LINE]);
    }
}
