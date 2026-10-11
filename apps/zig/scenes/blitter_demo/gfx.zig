// --------------------------------------------------------------------------
// Blitter demo — who draws: CHISEL (the hardware blitter, zg.Blitter) or ZIGGY
// (the CPU, soft.zig). The effects call the blitter's own API here, and key B
// flips `cpu`; both paths produce the same pixels (apps/blitter_headless.mjs
// compares every mode), so the only difference on screen is the frame rate.
// In CPU mode not one hwBlit() is issued — the harness counts them.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;
const Vec2 = zg.BlitVec2;
const soft = @import("soft.zig");

pub const Gfx = struct {
    hw: zg.Blitter = .{},
    sw: soft.Soft = .{},
    cpu: bool = false,

    pub fn init(self: *Gfx) void {
        self.hw.init();
        self.sw = .{};
        self.cpu = false;
    }

    pub fn fill(self: *Gfx, fb: *LogicalFB, x: i16, y: i16, w: u16, h: u16, color: u8) void {
        if (self.cpu) self.sw.fill(surface(fb), x, y, w, h, color) else self.hw.fill(fb, x, y, w, h, color);
    }

    pub fn clear(self: *Gfx, fb: *LogicalFB, color: u8) void {
        self.fill(fb, 0, 0, fb.fb_w, fb.fb_h, color);
    }

    pub fn triangleEx(self: *Gfx, fb: *LogicalFB, v0: Vec2, v1: Vec2, v2: Vec2, fg: u8, bg: u8, mt: zg.Minterm) void {
        if (!self.cpu) return self.hw.triangleEx(fb, v0, v1, v2, fg, bg, mt);
        self.sw.triangle(surface(fb), .{ sv(v0), sv(v1), sv(v2) }, fg, bg, @intFromEnum(mt));
    }

    pub fn bob(self: *Gfx, dst: *LogicalFB, dx: i16, dy: i16, src: *LogicalFB, sx: i16, sy: i16, w: u16, h: u16, key: u8) void {
        if (!self.cpu) return self.hw.bob(dst, dx, dy, src, sx, sy, w, h, key);
        self.sw.blit(surface(dst), dx, dy, surface(src), sx, sy, w, h, key);
    }

    pub fn blitCopy(self: *Gfx, dst: *LogicalFB, dx: i16, dy: i16, src: *LogicalFB, sx: i16, sy: i16, w: u16, h: u16) void {
        if (!self.cpu) return self.hw.blitCopy(dst, dx, dy, src, sx, sy, w, h);
        self.sw.blit(surface(dst), dx, dy, surface(src), sx, sy, w, h, null);
    }

    pub fn setHalftone(self: *Gfx, pattern: [16]u16) void {
        if (self.cpu) self.sw.setHalftone(pattern) else self.hw.setHalftone(pattern);
    }

    pub fn clearHalftone(self: *Gfx) void {
        if (self.cpu) self.sw.setHalftone(.{0} ** 16) else self.hw.clearHalftone();
    }
};

// A plane as the CPU blitter sees it. The height is the machine's rule
// (machine/blitter.zig dstHeight): a full-raster stride is 280 rows, any other 200.
fn surface(fb: *LogicalFB) soft.Surface {
    const h: u16 = if (fb.stride == zg.PHYSICAL_WIDTH) zg.PHYSICAL_HEIGHT else zg.HEIGHT;
    return .{ .px = fb.fb, .stride = fb.stride, .h = h };
}

fn sv(v: Vec2) soft.Vec2 {
    return .{ .x = v.x, .y = v.y };
}

// A re-strided view onto an existing plane's buffer, for treating a scratch
// plane as a packed tile ring / small render target (same backing bytes).
pub fn view(src: *LogicalFB, stride: u16, w: u16, h: u16) LogicalFB {
    var v = src.*;
    v.stride = stride;
    v.fb_w = w;
    v.fb_h = h;
    return v;
}
