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
const hw = @import("hardware"); // sealed video ABI header (named module)

// --------------------------------------------------------------------------
// Re-exports so scenes (in the separate `apps` module) can reach the whole open
// library through a single `@import("zigos")`, without relative paths escaping
// their module. Audio players are intentionally NOT re-exported here — they pull
// the audio chip ABI and belong only to the demo-audio build.
// --------------------------------------------------------------------------
pub const Console = @import("utils/debug.zig").Console;
pub const Starfield3D = @import("effects/starfield_3D.zig").Starfield3D;
pub const convertU8ArraytoColors = @import("utils/loaders.zig").convertU8ArraytoColors;
pub const Blitter = @import("blitter.zig").Blitter;
pub const BlitVec2 = @import("blitter.zig").Vec2;
pub const Minterm = @import("blitter.zig").Minterm;
pub const obj = @import("utils/obj_loader.zig");
pub const gui = @import("gui.zig");
pub const gem = @import("gem.zig");

// --------------------------------------------------------------------------
// Enum
// --------------------------------------------------------------------------
pub const Resolution = enum { truecolor, planes, medium };

// --------------------------------------------------------------------------
// Constants (re-exported from the SDK header so scenes keep their import paths)
// --------------------------------------------------------------------------
pub const PHYSICAL_WIDTH: u16 = hw.PHYSICAL_WIDTH;
pub const PHYSICAL_HEIGHT: u16 = hw.PHYSICAL_HEIGHT;
pub const RASTER_WIDTH: u16 = hw.RASTER_WIDTH;
pub const RASTER_HEIGHT: u16 = hw.RASTER_HEIGHT;
pub const MEDIUM_WIDTH: u16 = hw.MEDIUM_WIDTH;
pub const MEDIUM_HEIGHT: u16 = hw.MEDIUM_HEIGHT;
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

// VRAM pool bump allocator (Option B, pay-per-use): a normal plane costs 64000,
// a fullscreen plane 112000. `vram_top` is a byte offset from the region base.
var vram_top: usize = 0;

fn vramAlloc(bytes: usize) usize {
    const off = vram_top;
    vram_top += (bytes + 3) & ~@as(usize, 3); // keep 4-aligned
    return off;
}

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
    fb: [*]u8 = undefined, // -> LFB(id) in shared memory (up to PHYSICAL_WIDTH*PHYSICAL_HEIGHT indices)
    palette: [*]u32 = undefined, // -> PAL(id) in shared memory (256 RGBA entries)
    // Plane geometry: NORMAL is 320×200 (visible only); a plane can opt into
    // FULLSCREEN (400×280, stride 400) so its border columns hold independent
    // content — the sanctioned Option-B overscan (no physical-framebuffer poke).
    stride: u16 = WIDTH,
    fb_w: u16 = WIDTH,
    fb_h: u16 = HEIGHT,
    back_color: u8 = 0,
    id: u8 = 0,
    fb_hbl_handler: ?*const fn (*LogicalFB, *ZigOS, u16, u16) void = null,
    fb_hbl_handler_position: u16 = 0,
    is_enabled: bool = false,
    zigos: *ZigOS = undefined,

    // Point this plane's pixel view at `fb_off` (a byte offset into the region,
    // from the VRAM allocator) and publish it to the machine's FB_BASE register.
    fn bind(self: *LogicalFB, fb_off: usize) void {
        self.fb = @ptrFromInt(g_base + fb_off);
        self.palette = @ptrFromInt(g_base + hw.OFF_PAL + @as(usize, self.id) * hw.PAL_BYTES);
        writeU32(hw.REG_FB_BASE + @as(usize, self.id) * 4, @intCast(fb_off));
    }

    pub fn init(self: *LogicalFB, zigos: *ZigOS) void {
        self.stride = WIDTH;
        self.fb_w = WIDTH;
        self.fb_h = HEIGHT;
        var i: usize = 0;
        while (i < 256) : (i += 1) self.palette[i] = 0;
        self.clearFrameBuffer(0);
        self.zigos = zigos;
        self.is_enabled = false;
    }

    // Turn this plane into a fullscreen (400×280) overscan plane: coordinates are
    // now PHYSICAL (0..400, 0..280); the machine composites it across the whole
    // frame including the borders. The visible window stays at the same place.
    pub fn setFullscreen(self: *LogicalFB) void {
        self.stride = PHYSICAL_WIDTH;
        self.fb_w = PHYSICAL_WIDTH;
        self.fb_h = PHYSICAL_HEIGHT;
        writeU16(hw.REG_FB_STRIDE + @as(usize, self.id) * 2, hw.STRIDE_FULLSCREEN);
        // Allocate a fresh fullscreen buffer from the pool and repoint the plane
        // (the plane's original normal buffer is simply left unused).
        self.bind(vramAlloc(hw.FULLSCREEN_FB_BYTES));
        self.clearFrameBuffer(0);
    }

    // Turn this plane into a SCROLL plane: back it with a bigger-than-screen
    // buffer (buf_w x buf_h). Draw into it at buffer coordinates via the normal
    // methods; the visible 320x200 window is panned with setScroll()/setScrollFine().
    pub fn setScrollPlane(self: *LogicalFB, buf_w: u16, buf_h: u16) void {
        self.stride = buf_w;
        self.fb_w = buf_w;
        self.fb_h = buf_h;
        writeU16(hw.REG_FB_STRIDE + @as(usize, self.id) * 2, buf_w);
        writeU8(hw.REG_FB_MODE + @as(usize, self.id), hw.FB_MODE_SCROLL);
        self.bind(vramAlloc(@as(usize, buf_w) * @as(usize, buf_h)));
        self.clearFrameBuffer(0);
    }

    // Pan the visible window to buffer pixel (x, y) — coarse hardware scroll (moves
    // the plane's read base; the backing buffer / draw origin stays put).
    pub fn setScroll(self: *LogicalFB, x: u32, y: u32) void {
        const origin: u32 = @intCast(@intFromPtr(self.fb) - g_base);
        writeU32(hw.REG_FB_BASE + @as(usize, self.id) * 4, origin + y * self.stride + x);
    }

    // Per-line horizontal offset (added on top of setScroll). In SCROLL mode this
    // is re-read every scanline, so setting it from an HBL handler distorts the
    // image line-by-line (sine wobble / shear).
    pub fn setScrollFine(self: *LogicalFB, hs: u16) void {
        writeU16(hw.REG_HSCROLL + @as(usize, self.id) * 2, hs);
    }

    // Turn this plane into a MEDIUM-res plane (640x200, 1:1 into the raster).
    // Coordinates are 0..640 / 0..200; the machine composites it crisply (no
    // pixel doubling). Use 2 medium planes for a 4-colour GEM-style screen.
    pub fn setMediumPlane(self: *LogicalFB) void {
        self.stride = MEDIUM_WIDTH;
        self.fb_w = MEDIUM_WIDTH;
        self.fb_h = MEDIUM_HEIGHT;
        writeU16(hw.REG_FB_STRIDE + @as(usize, self.id) * 2, MEDIUM_WIDTH);
        writeU8(hw.REG_FB_MODE + @as(usize, self.id), hw.FB_MODE_MEDIUM);
        writeU8(hw.REG_RESOLUTION, hw.RES_MEDIUM); // default the screen to medium (HBL can switch per line)
        self.bind(vramAlloc(hw.MEDIUM_FB_BYTES));
        self.clearFrameBuffer(0);
    }

    // Medium OVERSCAN plane: an 800x280 buffer covering the WHOLE raster, borders
    // included (coordinates are physical; the visible window is at 80,40). Lets a
    // medium screen draw into the borders — the medium twin of setFullscreen().
    pub fn setMediumFullscreen(self: *LogicalFB) void {
        self.stride = RASTER_WIDTH;
        self.fb_w = RASTER_WIDTH;
        self.fb_h = RASTER_HEIGHT;
        writeU16(hw.REG_FB_STRIDE + @as(usize, self.id) * 2, RASTER_WIDTH);
        writeU8(hw.REG_FB_MODE + @as(usize, self.id), hw.FB_MODE_MEDIUM);
        writeU8(hw.REG_RESOLUTION, hw.RES_MEDIUM);
        self.bind(vramAlloc(hw.MEDIUM_FULL_FB_BYTES));
        self.clearFrameBuffer(0);
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
        if ((x < self.fb_w) and (y < self.fb_h)) {
            self.fb[@as(u32, y) * @as(u32, self.stride) + @as(u32, x)] = pal_entry;
        }
    }

    pub fn drawScanline(self: *LogicalFB, x1: u16, x2: u16, y: u16, pal_entry: u8) void {
        if ((x1 < self.fb_w) and (x2 < self.fb_w) and (y < self.fb_h)) {
            const delta = x2 - x1;
            var index: u32 = @as(u32, y) * @as(u32, self.stride) + @as(u32, x1);
            var i: u16 = 0;
            while (i < delta) : (i += 1) {
                self.fb[index] = pal_entry;
                index += 1;
            }
        }
    }

    pub fn clearFrameBuffer(self: *LogicalFB, pal_entry: u8) void {
        const n: u32 = @as(u32, self.fb_h) * @as(u32, self.stride);
        var i: u32 = 0;
        while (i < n) : (i += 1) self.fb[i] = pal_entry;
    }

    pub fn setFrameBufferHBLHandler(self: *LogicalFB, position: u16, handler: *const fn (*LogicalFB, *ZigOS, u16, u16) void) void {
        self.fb_hbl_handler = handler;
        self.fb_hbl_handler_position = position;
        // Publish to the machine: a non-zero id (plane+1) + the x position.
        writeU16(hw.REG_FB_HBL_ID + @as(usize, self.id) * 2, @as(u16, self.id) + 1);
        writeU16(hw.REG_FB_HBL_POS + @as(usize, self.id) * 2, position);
    }

    pub fn clearFrameBufferHBLHandler(self: *LogicalFB) void {
        self.fb_hbl_handler = null;
        writeU16(hw.REG_FB_HBL_ID + @as(usize, self.id) * 2, 0);
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
    physical_framebuffer: *[RASTER_HEIGHT][RASTER_WIDTH]u32 = undefined,
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

        // Allocate each plane a normal (320×200) framebuffer from the VRAM pool.
        // A scene upgrades a plane with setFullscreen() (allocates 400×280).
        vram_top = hw.OFF_VRAM;
        for (&self.lfbs, 0..) |*lfb, idx| {
            lfb.id = @intCast(idx);
            lfb.bind(vramAlloc(hw.NORMAL_FB_BYTES));
            lfb.init(self);
        }
    }

    // --- Features ---
    pub fn nop(self: *ZigOS) void {
        _ = self;
    }

    pub fn printText(self: *ZigOS, lfb: *LogicalFB, text: []const u8, x: u16, y: u16, fg_color_index: u8, bg_color_index: u8) void {
        const buffer = lfb.fb;
        // u32: a medium-res (640-wide) buffer exceeds u16 offsets (y*stride+x > 65535).
        const initial_position: u32 = @as(u32, y) * @as(u32, lfb.stride) + x;

        for (text, 0..) |char, nb| {
            const slice_offset_start: u16 = @as(u16, @intCast(char)) * (SYSTEM_FONT_WIDTH * SYSTEM_FONT_HEIGHT) - 1;
            const slice_offset_end: u16 = (@as(u16, @intCast(char)) + 1) * (SYSTEM_FONT_WIDTH * SYSTEM_FONT_HEIGHT);
            const char_data = self.system_font[slice_offset_start..slice_offset_end];
            var letter_pos: u32 = initial_position + @as(u32, @intCast(nb)) * SYSTEM_FONT_WIDTH;

            for (char_data, 0..) |pixel, idx| {
                buffer[letter_pos] = if (pixel == 1) fg_color_index else bg_color_index;
                if (idx > 0 and (idx % SYSTEM_FONT_WIDTH == 0)) {
                    letter_pos += (@as(u32, lfb.stride) - SYSTEM_FONT_WIDTH + 1);
                } else {
                    letter_pos += 1;
                }
            }
        }
    }

    // --- Framebuffer / register management ---
    pub fn setResolution(self: *ZigOS, res: Resolution) void {
        _ = self;
        writeU8(hw.REG_RESOLUTION, switch (res) {
            .planes => hw.RES_PLANES,
            .truecolor => hw.RES_TRUECOLOR,
            .medium => hw.RES_MEDIUM,
        });
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
