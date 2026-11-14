// --------------------------------------------------------------------------
// COPRO page 1: a slideshow that never stalls. The five TEX NEO SHOW pictures
// ship ZX0-packed (build.zig COPRO); while one shows, the next is depacked
// into a back buffer by a job, so the swap (every SHOW frames) is a copy.
// On ZIGGY the 64,000-byte depack lands inside the swap frame: the PEAK on
// the HUD's third line is that stall. On BARD it is spread between BARD's
// audio renders while ZIGGY keeps drawing.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const packed_assets = @import("packed_assets");
const pals = @import("../tex_neoshow/tables.zig");
const C = @import("common.zig");

pub const NAME = "ZX0 DEPACK";
const SHOW: u32 = 150; // frames a picture
const PIC: u32 = 320 * 200;
const PICS = packed_assets.copro;
const PALS = [_]*const [16][3]u8{ &pals.dragon_pal, &pals.midearth_pal, &pals.moreta_pal, &pals.porsche_pal, &pals.tut_ench_pal };

pub const Slides = struct {
    back: []u8 = &.{},
    next: u32 = 0, // the picture in the back buffer (or being depacked into it)
    pending: ?u32 = null,
    t: u32 = 0,

    pub fn enter(self: *Slides, ctx: *C.Ctx) void {
        if (self.back.len == 0) self.back = zg.mem.mustAlloc(u8, PIC);
        self.next = 0;
        self.t = 0;
        self.depack(ctx, 0);
    }

    /// Ask for picture `k` in the back buffer. The packed bytes are the cart's own data: in its
    /// memory, so BARD reads them where they are.
    fn depack(self: *Slides, ctx: *C.Ctx, k: u32) void {
        const p = PICS[k % PICS.len];
        self.next = k;
        self.pending = ctx.post(.zx0, &.{ ptr(p.ptr), @intCast(p.len), ptr(self.back.ptr), PIC });
    }

    pub fn frame(self: *Slides, ctx: *C.Ctx) void {
        defer self.t += 1;
        if (self.t % SHOW != 0) return;
        // Swap: the depacked picture to the screen, then the next one asked for.
        _ = ctx.wait(self.pending);
        self.pending = null;
        const pal = PALS[self.next % PALS.len];
        for (pal, 0..) |c, i| ctx.fb.setPaletteEntry(@intCast(i), .{ .r = c[0], .g = c[1], .b = c[2], .a = 255 });
        // The picture's middle 176 rows (12 above and 12 below give way to the HUD).
        @memcpy(ctx.pixels()[0 .. C.ROWS * C.W], self.back[12 * C.W ..][0 .. C.ROWS * C.W]);
        self.depack(ctx, self.next + 1);
    }

    pub fn leave(self: *Slides, ctx: *C.Ctx) void {
        _ = ctx.wait(self.pending);
        self.pending = null;
    }
};

pub fn ptr(p: anytype) u32 {
    return @intCast(@intFromPtr(p));
}
