// Harness cart for apps/tex_loader_fx_headless.mjs: depacks one ZX0 image with
// its depack effect (here fx = tex_loader) and nothing else. Not a scene and not
// in build.zig's cart list: the harness compiles it with apps/zig/demo_main.zig,
// passing the packed image as the `tex_packed` module it generates.
//
// The harness reads the result back through the exports below and compares the
// depacked bytes with the original file.
const zg = @import("zigos");
const hw = @import("hardware");
const DepackFx = @import("depackers").depack_fx.Runner(zg, null);
const tex_packed = @import("tex_packed");

var depack: DepackFx = undefined;
var dst: []u8 = &.{};
/// 0 depacking, 1 done, 2 failed, 3 could not start
var state: u32 = 0;

export fn texState() u32 {
    return state;
}
export fn texWritten() u32 {
    return if (state == 3) 0 else depack.stream.written();
}
export fn texTotal() u32 {
    return @intCast(dst.len);
}
export fn texDstPtr() [*]u8 {
    return dst.ptr;
}

pub const Cart = struct {
    pub fn init(self: *Cart, zigos: *zg.ZigOS) void {
        _ = self;
        const len = @import("depackers").zx0.depackedLen(tex_packed.image) orelse return fail();
        if (hw.hwRamFree() < len) return fail();
        dst = @as([*]u8, @ptrFromInt(hw.hwRamBase() + hw.hwRamUsed()))[0..len];
        if (!depack.start(zigos, tex_packed.image, dst, tex_packed.bytes_per_line)) return fail();
    }

    fn fail() void {
        state = 3;
        zg.Console.log("tex_loader_fx: could not start the depack", .{});
    }

    pub fn update(self: *Cart, zigos: *zg.ZigOS, dt: f32) void {
        _ = .{ self, dt };
        if (state != 0) return;
        state = switch (depack.frame(zigos)) {
            .more => 0,
            .done => 1,
            .failed => 2,
        };
    }

    pub fn render(self: *Cart, zigos: *zg.ZigOS, dt: f32) void {
        _ = .{ self, zigos, dt };
    }
};
