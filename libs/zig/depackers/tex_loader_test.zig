// The TEX loader effect driven end to end: depack_fx.Runner over a real packed
// asset, on a stand-in ZigOS (planes as plain buffers), checking what each frame
// shows against the depack's progress and what the machine is left with.
//
//   zig test libs/zig/depackers/tex_loader_test.zig      (run from the repo root)
const std = @import("std");
const zx0 = @import("zx0.zig");
const zx0_pack = @import("zx0_pack.zig");
const depack_fx = @import("depack_fx.zig");
const tex_loader = @import("tex_loader.zig");

const gpa = std.testing.allocator;

/// Just enough of ZigOS for Runner: the names and shapes it touches.
const MockZg = struct {
    pub const WIDTH: u16 = 320;
    pub const HEIGHT: u16 = 200;
    pub const PHYSICAL_HEIGHT: u16 = 280;
    pub const Color = struct { r: u8, g: u8, b: u8, a: u8 };

    pub const Fb = struct {
        fb: [*]u8,
        stride: u16 = WIDTH,
        fb_w: u16 = WIDTH,
        fb_h: u16 = HEIGHT,
        is_enabled: bool = false,
        pal: [256]Color = [_]Color{.{ .r = 0, .g = 0, .b = 0, .a = 0 }} ** 256,

        pub fn setPaletteEntry(self: *Fb, e: u8, c: Color) void {
            self.pal[e] = c;
        }
        pub fn getPaletteEntry(self: *Fb, e: u8) Color {
            return self.pal[e];
        }
        pub fn clearFrameBuffer(self: *Fb, e: u8) void {
            @memset(self.fb[0 .. @as(usize, self.stride) * self.fb_h], e);
        }
        pub fn drawScanline(self: *Fb, x1: u16, x2: u16, y: u16, e: u8) void {
            @memset(self.fb[@as(usize, y) * self.stride + x1 .. @as(usize, y) * self.stride + x2 + 1], e);
        }
    };

    pub const ZigOS = struct {
        lfbs: [4]Fb,
        hbl_handler: ?*const fn (*ZigOS, u16) void = null,
        bg: Color = .{ .r = 1, .g = 2, .b = 3, .a = 255 },

        pub fn getBackgroundColor(self: *ZigOS) Color {
            return self.bg;
        }
        pub fn setBackgroundColor(self: *ZigOS, c: Color) void {
            self.bg = c;
        }
        pub fn setHBLHandler(self: *ZigOS, h: *const fn (*ZigOS, u16) void) void {
            self.hbl_handler = h;
        }
        pub fn removeHBLHandler(self: *ZigOS) void {
            self.hbl_handler = null;
        }
        pub fn printText(self: *ZigOS, lfb: *Fb, text: []const u8, x: i16, y: i16, fg: u8, bg: u8) void {
            _ = .{ self, lfb, text, x, y, fg, bg };
        }
    };
};

const Runner = depack_fx.Runner(MockZg, null);

fn countInk(pixels: []const u8) !usize {
    var n: usize = 0;
    for (pixels) |p| switch (p) {
        0 => {},
        depack_fx.TEX_INK => n += 1,
        else => return error.StrayPixel,
    };
    return n;
}

fn readAsset(path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, gpa, .limited(8 << 20));
}

test "the TEX loader assembles the main menu panel as a real asset depacks, then restores the machine" {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const panel_file = try readAsset("apps/zig/assets/screens/union_demo/loader_main_menu.txt");
    defer gpa.free(panel_file);
    const panel = try zx0_pack.parsePanel(arena.allocator(), panel_file);
    const data = try readAsset("apps/zig/assets/screens/union_intro/wab.raw");
    defer gpa.free(data);
    const image = try zx0_pack.pack(gpa, data, .{ .fx = .tex_loader, .panel = panel });
    defer gpa.free(image);
    const dst = try gpa.alloc(u8, data.len);
    defer gpa.free(dst);

    var planes: [4][320 * 200]u8 = undefined;
    var zigos = MockZg.ZigOS{ .lfbs = undefined };
    for (&zigos.lfbs, &planes) |*fb, *buf| fb.* = .{ .fb = buf };
    zigos.lfbs[1].is_enabled = true;
    zigos.lfbs[0].pal[1] = .{ .r = 9, .g = 9, .b = 9, .a = 255 };

    // the whole panel landed, drawn off to the side: what the last byte shows
    var full_buf: [320 * 200]u8 = undefined;
    var full_fb = MockZg.Fb{ .fb = &full_buf };
    tex_loader.draw(&full_fb, panel.chars, panel.cols, tex_loader.timelineEnd(@intCast(panel.chars.len)), depack_fx.TEX_INK);
    const full = try countInk(&full_buf);
    try std.testing.expect(full > 1000);

    var runner: Runner = undefined;
    try std.testing.expect(runner.start(&zigos, image, dst, 1));
    try std.testing.expect(zigos.lfbs[0].is_enabled and !zigos.lfbs[1].is_enabled);
    try std.testing.expectEqual(@as(usize, 0), try countInk(&planes[0])); // letter 0 has not left y 246
    try std.testing.expectEqual(tex_loader.INK.r, zigos.lfbs[0].pal[depack_fx.TEX_INK].r);

    var frames: usize = 0;
    var last: usize = 0;
    var saw_middle = false;
    while (true) : (frames += 1) {
        const progress = runner.frame(&zigos);
        if (progress != .more) {
            try std.testing.expectEqual(zx0.Progress.done, progress);
            break;
        }
        const ink = try countInk(&planes[0]);
        try std.testing.expect(ink >= last); // letters only ever arrive
        last = ink;
        if (!saw_middle and runner.stream.written() * 2 >= runner.stream.total()) {
            saw_middle = true;
            try std.testing.expect(ink > full / 4 and ink < full * 3 / 4);
        }
    }
    try std.testing.expect(saw_middle and frames > 20);
    try std.testing.expect(last > full * 9 / 10); // nearly assembled on the last frame before ready
    try std.testing.expectEqualSlices(u8, data, dst);
    // put back: plane cleared, palette, enables, background
    try std.testing.expectEqual(@as(usize, 0), try countInk(&planes[0]));
    try std.testing.expectEqual(@as(u8, 9), zigos.lfbs[0].pal[1].r);
    try std.testing.expect(!zigos.lfbs[0].is_enabled and zigos.lfbs[1].is_enabled);
    try std.testing.expectEqual(@as(u8, 1), zigos.getBackgroundColor().r);
}

test "on an overscan plane the panel sits in the 320x200 window and flying letters stay clipped to it" {
    var buf: [400 * 280]u8 = undefined;
    var fb = MockZg.Fb{ .fb = &buf, .stride = 400, .fb_w = 400, .fb_h = 280 };
    const chars = "A" ** (zx0.MAX_PANEL_COLS * zx0.MAX_PANEL_ROWS); // 'A' inks its top row
    const n: u32 = chars.len;
    for ([_]u32{ tex_loader.timelineEnd(n), 1234, 5555 }) |t| {
        tex_loader.draw(&fb, chars, zx0.MAX_PANEL_COLS, t, depack_fx.TEX_INK);
        for (0..280) |y| for (0..400) |x| {
            if (buf[y * 400 + x] != 0) try std.testing.expect(x >= 40 and x < 360 and y >= 40 and y < 240);
        };
    }
    // the tallest, widest panel reaches the window's top cell row and last cell
    // column, and nothing lands left of x 80
    tex_loader.draw(&fb, chars, zx0.MAX_PANEL_COLS, tex_loader.timelineEnd(n), depack_fx.TEX_INK);
    var min_x: usize = 400;
    var max_x: usize = 0;
    var min_y: usize = 280;
    var max_y: usize = 0;
    for (0..280) |y| for (0..400) |x| if (buf[y * 400 + x] != 0) {
        min_x = @min(min_x, x);
        max_x = @max(max_x, x);
        min_y = @min(min_y, y);
        max_y = @max(max_y, y);
    };
    try std.testing.expect(min_x >= 40 + 80 and min_x < 40 + 88);
    try std.testing.expect(max_x >= 40 + 312 and max_x < 360);
    try std.testing.expect(min_y >= 40 and min_y < 40 + 8);
    try std.testing.expect(max_y >= 40 + 184 and max_y < 240);
}
