// --------------------------------------------------------------------------
// The chunky engine's backend on the machine: surfaces are planes (DISPLAY =
// the shown plane, the two ring buffers two DISABLED planes, which FRESCO never
// composites), every op is one CHISEL op except andMask, which is 16 px of CPU
// word stores (cheaper than a blit's ~1,100-cycle call on the board).
// soft_gpu.zig is the same contract in arrays; the native test runs it.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;

pub const ChiselGpu = struct {
    blit: zg.Blitter,
    fbs: [3]*LogicalFB,
    /// A source view whose stride is 0: blitCopy reads its ONE row on every
    /// destination row (the trail doubles). Kept here so a call stores only
    /// the row pointer, not a whole LogicalFB on the stack.
    row_view: LogicalFB,

    pub fn init(self: *ChiselGpu, fbs: [3]*LogicalFB) void {
        self.blit = .{};
        self.blit.init();
        self.fbs = fbs;
        self.row_view = fbs[0].*;
        self.row_view.stride = 0;
    }

    pub fn copy(self: *ChiselGpu, dst: u8, dx: u16, dy: u16, src: u8, sx: u16, sy: u16, w: u16, h: u16) void {
        self.blit.blitCopy(self.fbs[dst], @intCast(dx), @intCast(dy), self.fbs[src], @intCast(sx), @intCast(sy), w, h);
    }

    pub fn copyDouble(self: *ChiselGpu, dst: u8, dx: u16, dy: u16, src: u8, sx: u16, sy: u16, w: u16) void {
        const s = self.fbs[src];
        self.row_view.fb = s.fb + @as(usize, sy) * s.stride;
        self.blit.blitCopy(self.fbs[dst], @intCast(dx), @intCast(dy), &self.row_view, @intCast(sx), 0, w, 2);
    }

    pub fn image(self: *ChiselGpu, dst: u8, dx: u16, dy: u16, pixels: []const u8, src_w: usize, sx: u16, sy: u16, w: u16, h: u16) void {
        self.blit.blitImage(self.fbs[dst], @intCast(dx), @intCast(dy), pixels, @intCast(src_w), sx, sy, w, h, null);
    }

    pub fn fill(self: *ChiselGpu, dst: u8, x: u16, y: u16, w: u16, h: u16, v: u8) void {
        self.blit.fill(self.fbs[dst], @intCast(x), @intCast(y), w, h, v);
    }

    /// Indices &= keep over w px of one row. The wedge's groups are 8-px
    /// aligned, so this is w/4 aligned word read-modify-writes.
    pub fn andMask(self: *ChiselGpu, dst: u8, x: u16, y: u16, w: u16, keep: u8) void {
        const fb = self.fbs[dst];
        const at = fb.fb + @as(usize, y) * fb.stride + x;
        const k4: u32 = @as(u32, keep) * 0x01010101;
        if (@intFromPtr(at) % 4 == 0 and w % 4 == 0) {
            const words: [*]u32 = @ptrCast(@alignCast(at));
            for (0..w / 4) |i| words[i] &= k4;
        } else {
            for (at[0..w]) |*p| p.* &= keep;
        }
    }
};
