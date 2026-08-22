// --------------------------------------------------------------------------
// ZigOS — the OPEN OS/library layer, built ON TOP of the sealed machine via
// sdk/hardware.zig (memory-mapped ABI).
//
// The public API (Color, Resolution, LogicalFB, ZigOS, RenderTarget) is
// UNCHANGED from the pre-seal version, so existing effects and scenes compile
// as-is. What changed is the *backing store*: LogicalFB.fb / .palette, the
// physical framebuffer, and the video registers now live in the shared video
// hardware region owned by machine-video.wasm, instead of in ZigOS's own struct.
// HBL handlers stay Zig function pointers here; the machine reaches them only
// through integer ids via dispatchHBL().
// --------------------------------------------------------------------------
const std = @import("std");
const hw = @import("sdk/hardware.zig");
const Console = @import("utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Enum
// --------------------------------------------------------------------------
pub const Resolution = enum { truecolor, planes };

// --------------------------------------------------------------------------
// Constants (re-exported from the SDK header so scenes keep their import paths)
// --------------------------------------------------------------------------
pub const PHYSICAL_WIDTH: u16 = hw.PHYSICAL_WIDTH;
pub const PHYSICAL_HEIGHT: u16 = hw.PHYSICAL_HEIGHT;
pub const WIDTH: u16 = hw.WIDTH;
pub const HEIGHT: u16 = hw.HEIGHT;
pub const NB_PLANES: u8 = hw.NB_PLANES;
pub const HORIZONTAL_BORDERS_WIDTH: u16 = hw.HORIZONTAL_BORDERS_WIDTH;
pub const VERTICAL_BORDERS_HEIGHT: u16 = hw.VERTICAL_BORDERS_HEIGHT;
pub const SCOPE_LEN: usize = 128; // per-channel audio scope length (matches audio engine)

const SYSTEM_FONT = @embedFile("assets/fonts/system_font_atari_1bit.raw");
const SYSTEM_FONT_WIDTH = 8;
const SYSTEM_FONT_HEIGHT = 8;

// --------------------------------------------------------------------------
// Video hardware base — discovered from the sealed machine at init, then used
// to compute all framebuffer/palette/register addresses in shared memory.
// --------------------------------------------------------------------------
var g_base: usize = 0;

inline fn writeU8(off: usize, v: u8) void {
    @as(*u8, @ptrFromInt(g_base + off)).* = v;
}
inline fn writeU16(off: usize, v: u16) void {
    std.mem.writeInt(u16, @as(*[2]u8, @ptrFromInt(g_base + off)), v, .little);
}
inline fn writeU32(off: usize, v: u32) void {
    std.mem.writeInt(u32, @as(*[4]u8, @ptrFromInt(g_base + off)), v, .little);
}
inline fn readU32(off: usize) u32 {
    return std.mem.readInt(u32, @as(*[4]u8, @ptrFromInt(g_base + off)), .little);
}

// --------------------------------------------------------------------------
// Structs
// --------------------------------------------------------------------------
pub const RenderBuffer = struct {
    buffer: []u8 = undefined,
    width: u16 = undefined,
    height: u16 = undefined,
};

pub const RenderTarget = union(enum) {
    fb: *LogicalFB,
    render_buffer: *RenderBuffer,

    pub fn clearFrameBuffer(self: RenderTarget, pal_entry: u8) void {
        switch (self) {
            .fb => |fb| fb.clearFrameBuffer(pal_entry),
            .render_buffer => |rbuf| {
                var i: u32 = 0;
                while (i < rbuf.buffer.len) : (i += 1) rbuf.buffer[i] = pal_entry;
            },
        }
    }

    pub fn setPixelValue(self: RenderTarget, x: u16, y: u16, pal_entry: u8) void {
        switch (self) {
            .fb => |fb| fb.setPixelValue(x, y, pal_entry),
            .render_buffer => |rbuf| {
                if ((x < rbuf.width) and (y < rbuf.height)) {
                    const index: u32 = @as(u32, y) * @as(u32, rbuf.width) + @as(u32, x);
                    rbuf.buffer[index] = pal_entry;
                }
            },
        }
    }
};

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn toRGBA(self: Color) u32 {
        return (@as(u32, self.a) << 24) | (@as(u32, self.b) << 16) | (@as(u32, self.g) << 8) | (@as(u32, self.r));
    }

    pub fn fromRGBA(v: u32) Color {
        return .{
            .r = @truncate(v),
            .g = @truncate(v >> 8),
            .b = @truncate(v >> 16),
            .a = @truncate(v >> 24),
        };
    }
};

// A LogicalFB is now a thin VIEW onto the shared video region: `fb` and `palette`
// point into machine-owned memory. The method surface is identical to before.
pub const LogicalFB = struct {
    fb: [*]u8 = undefined, // -> LFB(id) in shared memory (WIDTH*HEIGHT palette indices)
    palette: [*]u32 = undefined, // -> PAL(id) in shared memory (256 RGBA entries)
    back_color: u8 = 0,
    id: u8 = 0,
    fb_hbl_handler: ?*const fn (*LogicalFB, *ZigOS, u16, u16) void = null,
    fb_hbl_handler_position: u16 = 0,
    is_enabled: bool = false,
    zigos: *ZigOS = undefined,

    fn bind(self: *LogicalFB) void {
        self.fb = @ptrFromInt(g_base + hw.OFF_LFB + @as(usize, self.id) * hw.LFB_BYTES);
        self.palette = @ptrFromInt(g_base + hw.OFF_PAL + @as(usize, self.id) * hw.PAL_BYTES);
    }

    pub fn init(self: *LogicalFB, zigos: *ZigOS) void {
        var i: usize = 0;
        while (i < 256) : (i += 1) self.palette[i] = 0;
        self.clearFrameBuffer(0);
        self.zigos = zigos;
        self.is_enabled = false;
    }

    pub fn getRenderTarget(self: *LogicalFB) RenderTarget {
        return RenderTarget{ .fb = self };
    }

    // --- Palette management ---
    pub fn setPalette(self: *LogicalFB, entries: [256]Color) void {
        for (entries, 0..) |c, i| self.palette[i] = c.toRGBA();
    }

    pub fn setPaletteEntry(self: *LogicalFB, entry: u8, value: Color) void {
        self.palette[entry] = value.toRGBA();
    }

    pub fn getPaletteEntry(self: *LogicalFB, entry: u8) Color {
        return Color.fromRGBA(self.palette[entry]);
    }

    pub fn setFramebufferBackgroundColor(self: *LogicalFB, pal_entry: u8) void {
        self.back_color = pal_entry;
    }

    pub fn setPixelValue(self: *LogicalFB, x: u16, y: u16, pal_entry: u8) void {
        if ((x < WIDTH) and (y < HEIGHT)) {
            self.fb[@as(u32, y) * @as(u32, WIDTH) + @as(u32, x)] = pal_entry;
        }
    }

    pub fn drawScanline(self: *LogicalFB, x1: u16, x2: u16, y: u16, pal_entry: u8) void {
        if ((x1 < WIDTH) and (x2 < WIDTH) and (y < HEIGHT)) {
            const delta = x2 - x1;
            var index: u32 = @as(u32, y) * @as(u32, WIDTH) + @as(u32, x1);
            var i: u16 = 0;
            while (i < delta) : (i += 1) {
                self.fb[index] = pal_entry;
                index += 1;
            }
        }
    }

    pub fn clearFrameBuffer(self: *LogicalFB, pal_entry: u8) void {
        var i: u32 = 0;
        while (i < hw.LFB_BYTES) : (i += 1) self.fb[i] = pal_entry;
    }

    pub fn setFrameBufferHBLHandler(self: *LogicalFB, position: u16, handler: *const fn (*LogicalFB, *ZigOS, u16, u16) void) void {
        self.fb_hbl_handler = handler;
        self.fb_hbl_handler_position = position;
        // Publish to the machine: a non-zero id (plane+1) + the x position.
        writeU16(hw.REG_FB_HBL_ID + @as(usize, self.id) * 2, @as(u16, self.id) + 1);
        writeU16(hw.REG_FB_HBL_POS + @as(usize, self.id) * 2, position);
    }
};

// --------------------------------------------------------------------------
// Zig OS
// --------------------------------------------------------------------------
pub const ZigOS = struct {
    background_color: Color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 },
    // View onto the shared physical framebuffer. Writing it is the out-of-ABI
    // "overscan" escape hatch (§2: memory is not sealed, only code is); the
    // sanctioned way to reach the borders is RESOLUTION + a border HBL handler.
    physical_framebuffer: *[PHYSICAL_HEIGHT][PHYSICAL_WIDTH]u32 = undefined,
    lfbs: [NB_PLANES]LogicalFB = undefined,
    hbl_handler: ?*const fn (*ZigOS, u16) void = null,
    system_font: []const u8 = undefined,
    // Mirror of the audio thread's YM2149 registers, pushed in from JS so scenes
    // can visualize the chip. 0..13 are the standard PSG registers.
    ym_regs: [16]u8 = [_]u8{0} ** 16,
    // Active audio player (0 none, 1 MOD, 2 YM, 3 sample) + per-channel scope
    // captures, both pushed in from JS for the music scene's oscilloscope.
    audio_mode: u8 = 0,
    scopes: [4][SCOPE_LEN]f32 = std.mem.zeroes([4][SCOPE_LEN]f32),

    pub fn init(self: *ZigOS) void {
        g_base = @intCast(hw.hwVideoBase());
        Console.log("ZigOS: video hardware base @ {x}", .{g_base});

        self.physical_framebuffer = @ptrFromInt(g_base + hw.OFF_PFB);
        self.system_font = SYSTEM_FONT;
        self.hbl_handler = null;

        // default registers
        writeU8(hw.REG_RESOLUTION, hw.RES_PLANES);
        self.background_color = Color{ .r = 20, .g = 20, .b = 20, .a = 255 };
        writeU32(hw.REG_BACKGROUND, self.background_color.toRGBA());

        for (&self.lfbs, 0..) |*lfb, idx| {
            lfb.id = @intCast(idx);
            lfb.bind();
            lfb.init(self);
        }
    }

    // --- Features ---
    pub fn nop(self: *ZigOS) void {
        _ = self;
    }

    pub fn printText(self: *ZigOS, lfb: *LogicalFB, text: []const u8, x: u16, y: u16, fg_color_index: u8, bg_color_index: u8) void {
        const buffer = lfb.fb;
        const initial_position: u16 = y * WIDTH + x;

        for (text, 0..) |char, nb| {
            const slice_offset_start: u16 = @as(u16, @intCast(char)) * (SYSTEM_FONT_WIDTH * SYSTEM_FONT_HEIGHT) - 1;
            const slice_offset_end: u16 = (@as(u16, @intCast(char)) + 1) * (SYSTEM_FONT_WIDTH * SYSTEM_FONT_HEIGHT);
            const char_data = self.system_font[slice_offset_start..slice_offset_end];
            var letter_pos = initial_position + (@as(u16, @intCast(nb)) * SYSTEM_FONT_WIDTH);

            for (char_data, 0..) |pixel, idx| {
                buffer[letter_pos] = if (pixel == 1) fg_color_index else bg_color_index;
                if (idx > 0 and (idx % SYSTEM_FONT_WIDTH == 0)) {
                    letter_pos += (WIDTH - SYSTEM_FONT_WIDTH + 1);
                } else {
                    letter_pos += 1;
                }
            }
        }
    }

    // --- Framebuffer / register management ---
    pub fn setResolution(self: *ZigOS, res: Resolution) void {
        _ = self;
        writeU8(hw.REG_RESOLUTION, if (res == .planes) hw.RES_PLANES else hw.RES_TRUECOLOR);
    }

    pub fn setBackgroundColor(self: *ZigOS, color: Color) void {
        self.background_color = color;
        writeU32(hw.REG_BACKGROUND, color.toRGBA());
    }

    pub fn getBackgroundColor(self: *ZigOS) Color {
        _ = self;
        return Color.fromRGBA(readU32(hw.REG_BACKGROUND));
    }

    pub fn setHBLHandler(self: *ZigOS, handler: *const fn (*ZigOS, u16) void) void {
        self.hbl_handler = handler;
        writeU16(hw.REG_GLOBAL_HBL_ID, hw.HBL_GLOBAL_ID);
    }

    pub fn removeHBLHandler(self: *ZigOS) void {
        self.hbl_handler = null;
        writeU16(hw.REG_GLOBAL_HBL_ID, 0);
    }

    // Called (via the demo module's exported hblDispatch) by the sealed machine
    // when the render pipeline reaches an HBL point. Integer ids in, Zig handler
    // calls out — the machine never holds a function pointer.
    pub fn dispatchHBL(self: *ZigOS, id: u32, plane: u32, line: u32, x: u32) void {
        if (id == hw.HBL_GLOBAL_ID) {
            if (self.hbl_handler) |h| h(self, @intCast(line));
        } else {
            const fb = &self.lfbs[@intCast(plane)];
            if (fb.fb_hbl_handler) |h| h(fb, self, @intCast(line), @intCast(x));
        }
    }
};
