// --------------------------------------------------------------------------
// Phase 4's dot figure, as the original builds it (RAM at load base $aa9a):
//   * $1108c generates a 3201-dot plot routine: dot i sits at x = T[i] + 64,
//     T = the $1b9d6 walk table (rows.raw), each dot an `or.b` of one bit
//     into ONE bitplane of the page;
//   * every frame ($13a74) one more word of the same table, read as a row,
//     goes into a 4000-entry ring ($6cf9c, mirrored 8000 bytes on) kept as
//     DIFFERENCES: the newest row at the head, the old head reduced by it.
//     The plot walks the ring from the head adding each word to its pointer,
//     so dot i lands on the row read i frames ago: x from the table now, y
//     from the table i frames back — the "3D" figure is that Lissajous;
//   * $111aa first clears the plane it is about to plot into, over the box
//     rows 0..199 x 64..271, and the plane advances every second frame:
//     with two pages, each plane of a page is cleared and redrawn every 8
//     frames — four generations of the figure overlap, and the top palette
//     (pal4) colours the overlaps: the trails.
// The pages here are the ST's own planar layout (p4_page.zig mirrors them
// into the plane), so
// every step is the 68000's, byte for byte. $1113c's precalc runs the ring
// 3201 steps before the first frame. All integer.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const A = @import("assets.zig");
const Page = @import("p4_page.zig").Page;

pub const DOTS = 0xc81; // 3201
const RING = 4000; // words; the mirror follows at RING
const PLOT_BASE = 0x20; // lea $20(a0): the figure's x starts at 64
pub const PAGE_BYTES = @import("p4_page.zig").BYTES;

/// The ring and its mirror ($6cf9c .. $70e1e) as the machine's words, on
/// zg.mem (alloc(), once per cart load).
var ring: []u16 = &.{};
var head: usize = 0; // a1, as a word index into `ring`
var stream: usize = 0; // a0 into the $1b9d6 table, as a word index
pub var plane_off: u16 = 0; // $5f4ce: 0, 2, 4, 6 = bitplane 0..3
var toggle: u16 = 0; // $5f4d0

pub fn alloc() void {
    ring = zg.mem.mustAlloc(u16, 2 * RING + 2);
}

/// $1108c's ring set-up and $1113c's 3201 steps, then the plane state.
pub fn reset() void {
    @memset(ring, 0);
    ring[RING] = 0x7d00;
    head = 0;
    stream = 0;
    for (0..DOTS) |_| insert();
    plane_off = 0;
    toggle = 0;
}

/// One stream word into the ring ($13a74's head, $1113c's loop body).
fn insert() void {
    if (stream >= A.ROWS_N) stream = 0;
    const v = A.rows[stream];
    stream += 1;
    if (head == 0) head = RING;
    head -= 1;
    const d: u16 = v *% 160;
    ring[head + RING] = d;
    ring[head] = d;
    ring[head + RING + 1] -%= d;
    ring[head + 1] -%= d;
}

/// $111aa: advance the plane every second frame, clear it in the box.
pub fn clearBox(page: *const Page) void {
    toggle ^= 1;
    if (toggle == 0) {
        plane_off += 2;
        if (plane_off == 8) plane_off = 0;
    }
    for (0..200) |y| {
        const g0: usize = if (y == 0) 5 else 4; // the unrolled list skips row 0's group 4
        var g = g0;
        while (g <= 16) : (g += 1) {
            const at = y * 160 + g * 8 + plane_off; // move.w d0: both bytes
            page.set(at, 0);
            page.set(at + 1, 0);
        }
    }
}

/// $13a74: one stream step, then the 3201 dots into the current plane.
pub fn plot(page: *const Page) void {
    insert();
    var a0: i32 = @as(i32, plane_off) + PLOT_BASE;
    for (0..DOTS) |i| {
        a0 += @as(i16, @bitCast(ring[head + i]));
        const x = A.rows[i];
        const at = a0 + @as(i32, (x >> 4) * 8 + ((x & 15) >> 3));
        if (at < 0 or at >= PAGE_BYTES) continue; // never taken: rows stay 3..196
        page.orByte(@intCast(at), @as(u8, 0x80) >> @intCast(x & 7));
    }
}
