// --------------------------------------------------------------------------
// COPRO page 4: raw throughput. A 64 KB buffer, CRC-32'd every frame in 256
// chunks of 256 bytes by one crc32 job (zlib's CRC, a table at comptime, a
// word at a time). Each chunk is a cell, its colour the CRC's low nibble;
// every frame the cart flips a few bytes, and only the cells whose CRC moved
// are redrawn: an integrity map. On BARD the job is ~0.7 Mc (42 % of its
// frame: 128 KB was 84 %, too much beside the music).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const job = zg.bard.job;
const C = @import("common.zig");
const ptr = @import("slides.zig").ptr;

pub const NAME = "CRC-32 64 KB";
const BYTES: u32 = 64 * 1024;
const CHUNK_LOG: u32 = 8;
const CHUNKS: u32 = BYTES >> CHUNK_LOG; // 256: 32 x 8 cells
const COLS: u32 = 32;
const CW: u32 = 10;
const CH: u32 = 22;
const FLIPS: u32 = 3;

pub const CrcMap = struct {
    buf: []u32 = &.{},
    out: [2][]u32 = .{ &.{}, &.{} },
    shown: []u32 = &.{},
    pending: ?u32 = null,
    f: u32 = 0,
    crc: u32 = 0, // the last whole answer (the CRC of the chunks' CRCs)

    pub fn enter(self: *CrcMap, ctx: *C.Ctx) void {
        if (self.buf.len == 0) {
            self.buf = C.words(BYTES / 4);
            self.out = .{ C.words(CHUNKS), C.words(CHUNKS) };
            self.shown = C.words(CHUNKS);
        }
        for (self.buf, 0..) |*w, i| w.* = job.hash(@intCast(i), 0xC2C);
        @memset(self.shown, 0xFFFF_FFFF); // every cell drawn on the first answer
        C.clearRows(ctx.fb, 0);
        ctx.fb.setPaletteEntry(0, .{ .r = 0, .g = 0, .b = 0, .a = 255 });
        C.shades(ctx.fb, .{ 0, 40, 30 }, .{ 120, 255, 160 });
        self.f = 0;
        self.pending = self.kick(ctx, 0);
    }

    fn kick(self: *CrcMap, ctx: *C.Ctx, f: u32) u32 {
        return ctx.post(.crc32, &.{ ptr(self.buf.ptr), BYTES, CHUNK_LOG, ptr(self.out[f & 1].ptr) });
    }

    pub fn frame(self: *CrcMap, ctx: *C.Ctx) void {
        if (ctx.wait(self.pending)) |j| self.crc = j.result;
        const crcs = self.out[self.f & 1];
        for (crcs, self.shown, 0..) |c, *s, k| {
            if (c == s.*) continue;
            s.* = c;
            cell(ctx.pixels(), @intCast(k), C.SHADE + @as(u8, @intCast(c & 15)));
        }
        // A few bytes flipped, then the next frame's CRCs asked for (the job reads the buffer).
        const bytes: [*]u8 = @ptrCast(self.buf.ptr);
        for (0..FLIPS) |i| {
            const h = job.hash(@intCast(i), self.f);
            bytes[h & (BYTES - 1)] ^= @intCast((h >> 24) | 1);
        }
        self.pending = self.kick(ctx, self.f + 1);
        self.f += 1;
    }

    fn cell(px: [*]u8, k: u32, v: u8) void {
        const x0 = (k % COLS) * CW;
        const y0 = (k / COLS) * CH;
        for (0..CH - 1) |y| @memset(px[(y0 + y) * C.W + x0 ..][0 .. CW - 1], v);
    }

    pub fn leave(self: *CrcMap, ctx: *C.Ctx) void {
        _ = ctx.wait(self.pending);
        self.pending = null;
    }
};
