// --------------------------------------------------------------------------
// A size-switched linear copy: the CPU below COPY_MIN bytes, CHISEL above,
// the same bytes either way (a copy is a copy; the machine's BLIT and the
// board's CHISEL write exactly what @memcpy would).
//
// Why: on KESTREL every store is a DDR write, so a CPU copy costs ~2.74 cycles
// a byte, while a CHISEL copy costs ~1.3 a byte plus ~800 of fixed price (the
// hwBlit call, CHISEL's start and drain). Board bench, 2026-10-19 (cycles):
//
//     bytes    CPU memcpy    CHISEL copy (hwBlit, SRC_ABS)
//        64         116          819
//      1 K        ~1000         2332
//      8 K        22.5 K       11.6 K
//     64 K       179.5 K       84.3 K   (2.74 vs 1.29 c/B)
//
// The cp.* bench rows on the board (19 Oct, VRAM destination) put the crossover
// near 8 K: 2 K CPU 2270 / CHISEL 4173, 4 K 4443 / 7325, 8 K CHISEL 11.8 K
// (CPU ~22.5 K). COPY_MIN is 8 K.
//
// CHISEL writes only the video region (at or above OFF_VRAM, a plane's
// worth of rows per op: chisel.zig's run) and reads only the machine's
// readable windows (cart RAM, the video region, the ROM's RAM); an overlap
// would make the row order part of the result. Any of those, or a short copy:
// @memmove. The bytes go as rows of COPY_W, then a last short row.
// --------------------------------------------------------------------------
const hw = @import("hardware");
const chisel = @import("chisel.zig");
const Queue = @import("blit_queue.zig").Queue;
const plan = @import("effects/chisel_copy_plan.zig");

pub const COPY_MIN: usize = 8192; // bytes: below it the CPU copies (the tables above)
const COPY_W: u16 = 4096; // a row: the stride of both sides of the 2-D copy
const MAP = plan.Map{
    .vram = hw.OFF_VRAM,
    .region = hw.OFF_PFB + @as(usize, hw.RASTER_WIDTH) * hw.RASTER_HEIGHT * 4, // REGION_BYTES (memmap.zig)
    .cart = .{ hw.CART_RAM_BASE, hw.CART_RAM_TOP },
    .rom = .{ hw.ROM_RAM_BASE, hw.ROM_RAM_TOP },
};

/// dst[0..len] = src[0..len]: CHISEL when it is the faster and can do it, else
/// the CPU. Synchronous unless the cart opted into the lazy wait (BLIT_ASYNC):
/// then dst is only written for sure after its sync.
pub fn copy(base: usize, dst: []u8, src: []const u8) void {
    if (!eligible(base, dst, src)) return @memmove(dst, src[0..dst.len]);
    const sp = plan.split(dst.len, COPY_W);
    const rows: u16 = @intCast(sp.rows);
    const tail: u16 = @intCast(sp.tail);
    var ok = true;
    if (rows != 0) ok = chisel.copyRect(base, dst.ptr, COPY_W, src.ptr, COPY_W, COPY_W, rows, null);
    const at = @as(usize, rows) * COPY_W;
    if (tail != 0 and ok) ok = chisel.copyRect(base, dst.ptr + at, tail, src.ptr + at, tail, tail, 1, null);
    if (!ok) @memmove(dst, src[0..dst.len]); // never with eligible() true: kept so a wrong check costs speed, not bytes
}

/// The same as queued BLITs in `q` (zg.blit_queue): dst is written for sure
/// only after q.flush(). The CPU copies at once when CHISEL cannot.
pub fn copyQueued(q: *Queue, dst: []u8, src: []const u8) void {
    if (!eligible(q.base, dst, src)) {
        q.flush(); // the ops queued before this copy come first
        return @memmove(dst, src[0..dst.len]);
    }
    var done: usize = 0;
    const per: usize = @as(usize, COPY_W) * hw.HEIGHT; // the rows one op may reach on this stride
    while (dst.len - done >= COPY_W) {
        const rows: usize = @min((dst.len - done) / COPY_W, per / COPY_W);
        queueRect(q, dst.ptr + done, src.ptr + done, COPY_W, @intCast(rows));
        done += rows * COPY_W;
    }
    if (done < dst.len) queueRect(q, dst.ptr + done, src.ptr + done, @intCast(dst.len - done), 1);
}

fn queueRect(q: *Queue, dst: [*]u8, src: [*]const u8, w: u16, rows: u16) void {
    q.op(hw.BLIT_CMD_BLIT, &.{
        .{ .k = 0, .v = @as(u32, hw.MT_B) << 8 | @as(u32, hw.CON_USEB) << 16 }, // D = B, no clip, no key
        .{ .k = 1, .v = @as(u32, hw.CON2_SRC_ABS) << 24 },
        .{ .k = 4, .v = @intCast(@intFromPtr(src)) },
        .{ .k = 5, .v = w },
        .{ .k = 8, .v = @intCast(@intFromPtr(dst) - q.base) },
        .{ .k = 9, .v = w },
        .{ .k = 10, .v = @as(u32, w) | @as(u32, rows) << 16 },
        .{ .k = 11, .v = 0 },
    });
}

fn eligible(base: usize, dst: []u8, src: []const u8) bool {
    return src.len >= dst.len and plan.eligible(MAP, base, @intFromPtr(dst.ptr), @intFromPtr(src.ptr), dst.len, COPY_MIN);
}
