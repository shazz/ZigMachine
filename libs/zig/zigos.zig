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
pub const Boot = @import("effects/boot.zig").Boot;
pub const parallax = @import("effects/parallax.zig"); // Parallax(n) + Layer
pub const tilemap = @import("effects/tilemap.zig"); // TileSheet + Layer
pub const scrolltext2 = @import("effects/scrolltext2.zig"); // stride-agnostic scrolltext
pub const charpanel = @import("effects/charpanel.zig"); // self-writing character panel
pub const blit = @import("effects/blit.zig"); // clipped signed blits: Dst/Image/Ink
pub const palette = @import("effects/palette.zig"); // scale colours from a base palette (fades)
pub const scrollring = @import("effects/scrollring.zig"); // CODEF letter-ring scroller state
pub const pathchain = @import("effects/pathchain.zig"); // sprites trailing each other along one ripped path
pub const wave = @import("effects/wave.zig"); // CODEF FX.siny: SineSum + column-shifted strip blit
pub const spans = @import("effects/spans.zig"); // comptime ink runs of a sparse overlay
pub const zig3d = @import("effects/zig3d.zig"); // CODEF codef3D (three.js r49 canvas faces), replayed exactly
pub const canvas_poly = @import("effects/canvas_poly.zig"); // a doubled canvas's path fill, shown halved
pub const colour_bank = @import("effects/colour_bank.zig"); // per-frame RGB -> palette entry allocation
pub const ballfield = @import("effects/ballfield.zig"); // CODEF ballfield: 3D ball bobs flying at the viewer
pub const chrome_draw = @import("effects/chrome_draw.zig"); // Chrome's drawImage (of a part) at a fractional y: taps, mix, srcOver
pub const spanfont = @import("effects/spanfont.zig"); // big 1-bit font as ink runs, sampled at half resolution
pub const linepal = @import("effects/linepal.zig"); // rgb(); LinePalette below
/// Up to `n` palette entries per visible line, allocated per pixel colour, replayed by an HBL.
pub fn LinePalette(comptime n: usize) type {
    return linepal.LinePalette(LogicalFB, ZigOS, .{ .rows = HEIGHT, .visible_top = VERTICAL_BORDERS_HEIGHT }, n);
}
// per-line palette tables, one HBL per plane, always-physical rows
pub const copper = @import("effects/copper.zig").Copper(LogicalFB, ZigOS, .{
    .nb_planes = NB_PLANES,
    .rows = PHYSICAL_HEIGHT,
    .visible_top = VERTICAL_BORDERS_HEIGHT,
    .visible_rows = HEIGHT,
    .magic_x = OVERSCAN_MAGIC_X,
});

// Mid-line colour-0 writes (HW 1.6.0 BEAM), queued from the global HBL handler.
pub const beam = @import("effects/beam.zig").Beam(BeamRegs, .{
    .count = hw.REG_BEAM_COUNT,
    .dropped = hw.REG_BEAM_DROPPED,
    .table = hw.OFF_BEAM_TABLE,
    .max = hw.BEAM_MAX,
});
const BeamRegs = struct {
    pub const r16 = readU16;
    pub const w16 = writeU16;
    pub const r32 = readU32;
    pub const w32 = writeU32;
};

// Overscan HBL handlers for LogicalFB.openBorders(). On an overscan plane the
// line is PHYSICAL 0..279; the visible band is VERTICAL_BORDERS_HEIGHT..+HEIGHT.
pub fn flickerAllHbl(fb: *LogicalFB, _: *ZigOS, _: u16, _: u16) void {
    fb.flickerBorder();
}
fn flickerBandsHbl(fb: *LogicalFB, _: *ZigOS, line: u16, _: u16) void {
    if (line < VERTICAL_BORDERS_HEIGHT or line >= VERTICAL_BORDERS_HEIGHT + HEIGHT) fb.flickerBorder();
}
pub const convertU8ArraytoColors = @import("utils/loaders.zig").convertU8ArraytoColors;
pub const readU16Array = @import("utils/loaders.zig").readU16Array;
pub const readI16Array = @import("utils/loaders.zig").readI16Array;
pub const Blitter = @import("blitter.zig").Blitter;
pub const BlitVec2 = @import("blitter.zig").Vec2;
pub const Minterm = @import("blitter.zig").Minterm;
pub const obj = @import("utils/obj_loader.zig");
// GEM desktop + GUI toolkit moved to the ROM (rom/gem/); apps reach them via
// @import("rom"), keeping the machine < libs < ROM < apps layering clean.
pub const za = @import("utils/zalgebra.zig"); // vector/matrix math (Vec2/3/4, Mat4, perspective/camera/screen)

// Migrated-scenes re-exports (added for apps/scenes/* pre-reorg-import migration).
pub const Scrolltext = @import("effects/scrolltext.zig").Scrolltext;
pub const Background = @import("effects/background.zig").Background;
pub const Sprite = @import("effects/sprite.zig").Sprite;
pub const Bobs = @import("effects/bobs.zig").Bobs;
pub const Text = @import("effects/text.zig").Text;
pub const Starfield = @import("effects/starfield.zig").Starfield;
pub const StarfieldDirection = @import("effects/starfield.zig").StarfieldDirection;
pub const Dots3D = @import("effects/dots3d.zig").Dots3D;
pub const shapes = @import("effects/shapes.zig");
pub const wireframe = @import("effects/wireframe.zig").With(za); // 3D line objects from a .obj (obj.parseWire)
pub const Mandelbrot = @import("effects/mandelbrot.zig").Mandelbrot;

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
pub const OVERSCAN_MAGIC_X: u16 = hw.OVERSCAN_MAGIC_X; // register the overscan HBL here
pub const OVERSCAN_X_TOL: u16 = hw.OVERSCAN_X_TOL;
pub const NB_PLANES: u8 = hw.NB_PLANES;
// The VRAM pool and what a plane costs in it. vramAlloc() has NO pool guard —
// it bumps straight past the end into the physical framebuffer — so a scene that
// allocates a big backing buffer should bound-check its total at comptime, and
// it needs these numbers to do that without hardcoding the memory map.
pub const VRAM_BYTES: usize = hw.VRAM_BYTES;
pub const NORMAL_FB_BYTES: usize = hw.NORMAL_FB_BYTES;
pub const OVERSCAN_FB_BYTES: usize = hw.FULLSCREEN_FB_BYTES; // one 400x280 plane
pub const HORIZONTAL_BORDERS_WIDTH: u16 = hw.HORIZONTAL_BORDERS_WIDTH;
pub const VERTICAL_BORDERS_HEIGHT: u16 = hw.VERTICAL_BORDERS_HEIGHT;
pub const SCOPE_LEN: usize = 128; // per-channel audio scope length (matches audio engine)

const SYSTEM_FONT = @embedFile("assets/fonts/system_font_atari_1bit.raw");
const SYSTEM_FONT_WIDTH = 8;
const SYSTEM_FONT_HEIGHT = 8;

// The authentic ST 6x6 system font (used for icon labels, like GEM).
const SYSTEM_FONT_6 = @embedFile("assets/fonts/system_font_atari_6x6.raw");
pub const SMALL_FONT_WIDTH = 6;
pub const SMALL_FONT_HEIGHT = 6;

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
inline fn readU16(off: usize) u16 {
    return std.mem.readInt(u16, @as(*[2]u8, @ptrFromInt(g_base + off)), .little);
}
inline fn readU32(off: usize) u32 {
    return std.mem.readInt(u32, @as(*[4]u8, @ptrFromInt(g_base + off)), .little);
}

// --- Host song bridge ------------------------------------------------------
// Scenes request a tune BY NAME (a path under docs/music/) so the host stays
// generic — no per-scene playlist baked into the loader. The host polls
// takeSongRequest() and, when set, plays the file at songName* by extension.
var g_song_name: [64]u8 = [_]u8{0} ** 64;
var g_song_len: usize = 0;
var g_song_pending: bool = false;
var g_song_tune: u8 = 0;

pub fn requestSong(name: []const u8) void {
    requestSongTune(name, 0);
}

/// The reserved song name that asks the host to STOP whatever is playing (it
/// resets the audio players, as it does when a program ends). No file may use it.
pub const SONG_STOP = "none";

/// Silence the current tune, e.g. for a loader panel that plays no music.
pub fn stopSong() void {
    requestSong(SONG_STOP);
}

/// Same, for a multi-subtune image: `tune` counts from 1, and 0 means "the
/// image's own default". An SNDH can hold many songs (Leavin Teramis holds 11)
/// and the file name alone cannot say which one a screen wants.
pub fn requestSongTune(name: []const u8, tune: u8) void {
    const n = @min(name.len, g_song_name.len);
    @memcpy(g_song_name[0..n], name[0..n]);
    g_song_len = n;
    g_song_tune = tune;
    g_song_pending = true;
}
/// A ProTracker MOD started at `bpm` (32..255) instead of ProTracker's 125, for
/// a replay whose own default differs (TRSI's Falcon replay starts at 123). A
/// MOD has no subtunes, so the request's tune field carries the BPM; 0, what
/// requestSong sends, keeps 125.
pub fn requestModBpm(name: []const u8, bpm: u8) void {
    requestSongTune(name, bpm);
}
pub fn songTune() u8 {
    return g_song_tune;
}
pub fn takeSongRequest() bool {
    const p = g_song_pending;
    g_song_pending = false;
    return p;
}
pub fn songNamePtr() [*]u8 {
    return &g_song_name;
}
pub fn songNameLen() usize {
    return g_song_len;
}

// --- Disk drive (block reads) + streaming audio (docs/FLOPPY_DISK.md) ----------
// The mounted disk lives in the host; these bridges let a scene STREAM a file off
// it block-by-block into RAM (never holding it whole) and feed it to the audio
// ring. Addresses passed to the host are raw wasm addresses = byte offsets into
// the shared memory buffer.
extern fn diskReadBlock(block: u32, dst_off: u32) i32; // copy one 512 B block -> dst; returns bytes read (0 = none)
extern fn hostAudioStreamStart(rate: f32) void; // begin streaming raw playback (ring in song RAM)
extern fn hostAudioFeed(ptr: u32, len: u32) void; // append signed-8-bit samples to the ring
extern fn hostAudioStreamStop() void; // silence the ring (it loops until told otherwise)

pub const DISK_BLOCK: usize = 512;

// The machine-side disk reader (FAT lookup + file streaming) built on readBlock.
pub const disk = @import("disk.zig");

// Read one 512-byte disk block into dst (>= 512 bytes). Returns bytes read.
pub fn readBlock(block: u32, dst: []u8) i32 {
    return diskReadBlock(block, @intCast(@intFromPtr(dst.ptr)));
}
// Start streaming raw audio at `rate` Hz (signed 8-bit mono), then feed() chunks.
pub fn audioStreamStart(rate: f32) void {
    hostAudioStreamStart(rate);
}
pub fn audioFeed(bytes: []const u8) void {
    hostAudioFeed(@intCast(@intFromPtr(bytes.ptr)), @intCast(bytes.len));
}
// Stop streaming. The ring is a looping channel: it replays its contents until
// the machine says stop, so this is not optional at the end of a sample.
pub fn audioStreamStop() void {
    hostAudioStreamStop();
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

    // Turn this plane into an OVERSCAN plane: a 400×280 buffer in PHYSICAL coords
    // (0..400, 0..280). The borders stay CLOSED — only the visible 320×200 window
    // shows — until the scene "opens" a border with the authentic resolution-flicker
    // trick: call flickerBorder() from this plane's HBL handler, at OVERSCAN_MAGIC_X,
    // on the scanline of the border you want. See docs/HW_API.md "Opening the borders".
    pub fn setOverscanBuffer(self: *LogicalFB) void {
        self.stride = PHYSICAL_WIDTH;
        self.fb_w = PHYSICAL_WIDTH;
        self.fb_h = PHYSICAL_HEIGHT;
        writeU16(hw.REG_FB_STRIDE + @as(usize, self.id) * 2, hw.STRIDE_FULLSCREEN);
        writeU8(hw.REG_FB_MODE + @as(usize, self.id), hw.FB_MODE_OVERSCAN);
        self.bind(vramAlloc(hw.FULLSCREEN_FB_BYTES));
        self.clearFrameBuffer(0);
    }

    // Turn this plane into an OVERSCAN plane backed by a BIGGER-than-window buffer,
    // so the 400×280 overscan window can be panned across it with setScroll() —
    // hardware scroll and open borders at the same time. No machine change was
    // needed: renderPlaneOverscan() already reads the buffer through FB_BASE (the
    // pan point) with FB_STRIDE as the row pitch. Borders are still EARNED —
    // flickerBorder() from this plane's HBL at OVERSCAN_MAGIC_X, exactly as for
    // setOverscanBuffer(). Draw in buffer coords (0..buf_w, 0..buf_h), and keep
    // the pan inside 0..buf_w-PHYSICAL_WIDTH / 0..buf_h-PHYSICAL_HEIGHT.
    // NB: renderPlaneOverscan does NOT re-read HSCROLL, so there is no per-line
    // fine scroll in this mode (unlike FB_MODE_SCROLL).
    // A buffer SMALLER than the overscan window would make the machine read past
    // the allocation on every frame — a silent VRAM corruption, not a trap, since
    // nothing bounds-checks the composite. So the size is clamped up to the window
    // rather than trusted; the caller still owes the pan clamp above.
    pub fn setOverscanScrollPlane(self: *LogicalFB, buf_w: u16, buf_h: u16) void {
        const w = @max(buf_w, PHYSICAL_WIDTH);
        const h = @max(buf_h, PHYSICAL_HEIGHT);
        self.stride = w;
        self.fb_w = w;
        self.fb_h = h;
        writeU16(hw.REG_FB_STRIDE + @as(usize, self.id) * 2, w);
        writeU8(hw.REG_FB_MODE + @as(usize, self.id), hw.FB_MODE_OVERSCAN);
        self.bind(vramAlloc(@as(usize, w) * @as(usize, h)));
        self.clearFrameBuffer(0);
    }

    // Open a border, ST-style, from THIS plane's per-plane HBL handler: flicker the
    // resolution register (RES_MEDIUM -> RES_PLANES). The sealed machine can't trap
    // writes to shared memory, so we also bump REG_RES_FLICKER — the latch it samples
    // once per scanline. The plane's HBL must fire at OVERSCAN_MAGIC_X (± tolerance)
    // or that line's border shows garbage — a mistimed trick, exactly as on real HW.
    // Flicker in a border band (top/bottom) opens it from that row down; flicker on a
    // visible line opens both side borders for that line (re-open sides every line).
    pub fn flickerBorder(_: *LogicalFB) void {
        writeU8(hw.REG_RESOLUTION, hw.RES_MEDIUM);
        writeU8(hw.REG_RESOLUTION, hw.RES_PLANES);
        writeU16(hw.REG_RES_FLICKER, readU16(hw.REG_RES_FLICKER) +% 1);
    }

    pub const Borders = enum { all, top_bottom };

    // Make this an overscan plane and open its borders with the flicker trick:
    // .all flickers every line (top, sides, bottom), .top_bottom only the border
    // bands (MAXI). Replaces this plane's HBL handler; a scene that also needs
    // per-line rasters uses copper.install(fb, entries, .{ .flicker = true }).
    // Every enabled overscan plane needs this for itself: the machine replays a
    // plane's HBLs while rendering THAT plane.
    pub fn openBorders(self: *LogicalFB, which: Borders) void {
        self.setOverscanBuffer();
        self.setFrameBufferHBLHandler(OVERSCAN_MAGIC_X, switch (which) {
            .all => flickerAllHbl,
            .top_bottom => flickerBandsHbl,
        });
    }

    // True when this plane's per-plane HBL receives PHYSICAL lines 0..279 (overscan,
    // fullscreen, full-raster medium), false for LOGICAL lines 0..199 (normal, scroll,
    // medium) — machine/video.zig's renderPlane* loops.
    pub fn hblLinesArePhysical(self: *const LogicalFB) bool {
        const mode = @as(*const u8, @ptrFromInt(g_base + hw.REG_FB_MODE + @as(usize, self.id))).*;
        return switch (mode) {
            hw.FB_MODE_OVERSCAN, hw.FB_MODE_FULLSCREEN => true,
            hw.FB_MODE_MEDIUM => self.stride >= RASTER_WIDTH,
            else => false,
        };
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

    // Turn this plane into a MEDIUM-res plane covering the WHOLE 800x280 raster,
    // borders included — the medium twin of the low-res Option-B overscan. The
    // visible window is the centre 640x200 at (80,40); coordinates here are
    // PHYSICAL, so (0,0) is the top-left of the border.
    //
    // The sealed machine already does this: renderPlaneMedium() switches to
    // full-raster compositing when a plane's stride reaches RASTER_WIDTH, which is
    // the only signal it gets. So this is a plain ZigOS helper, not HW work — it
    // replaces the deleted setMediumFullscreen(), whose removal during the
    // overscan rework is what parked apps/zig/scenes/medium_overscan.zig.
    pub fn setMediumOverscan(self: *LogicalFB) void {
        self.stride = RASTER_WIDTH;
        self.fb_w = RASTER_WIDTH;
        self.fb_h = RASTER_HEIGHT;
        writeU16(hw.REG_FB_STRIDE + @as(usize, self.id) * 2, RASTER_WIDTH); // >= 800: the machine's cue
        writeU8(hw.REG_FB_MODE + @as(usize, self.id), hw.FB_MODE_MEDIUM);
        writeU8(hw.REG_RESOLUTION, hw.RES_MEDIUM);
        self.bind(vramAlloc(hw.MEDIUM_FULL_FB_BYTES)); // 224000, from the 1 MiB VRAM pool
        self.clearFrameBuffer(0);
    }

    // Switch an already-medium plane (setMediumPlane) between LOW (320, drawn
    // pixel-doubled) and MEDIUM (640, 1:1) at runtime WITHOUT reallocating: the
    // 640-wide buffer holds a 320 image too (stride 320 uses its first columns).
    // Redraw after switching (content is stride-dependent).
    pub fn setResLow(self: *LogicalFB) void {
        self.stride = WIDTH;
        self.fb_w = WIDTH;
        self.fb_h = HEIGHT;
        writeU16(hw.REG_FB_STRIDE + @as(usize, self.id) * 2, WIDTH);
        writeU8(hw.REG_FB_MODE + @as(usize, self.id), hw.FB_MODE_NORMAL);
        writeU8(hw.REG_RESOLUTION, hw.RES_PLANES);
    }
    pub fn setResMedium(self: *LogicalFB) void {
        self.stride = MEDIUM_WIDTH;
        self.fb_w = MEDIUM_WIDTH;
        self.fb_h = MEDIUM_HEIGHT;
        writeU16(hw.REG_FB_STRIDE + @as(usize, self.id) * 2, MEDIUM_WIDTH);
        writeU8(hw.REG_FB_MODE + @as(usize, self.id), hw.FB_MODE_MEDIUM);
        writeU8(hw.REG_RESOLUTION, hw.RES_MEDIUM);
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
// A clipping rectangle for text, in framebuffer pixels. UNBOUNDED is "the whole
// framebuffer" — blitGlyphs always clips to that as well.
pub const Clip = struct {
    x0: i16,
    y0: i16,
    x1: i16,
    y1: i16,
    pub const UNBOUNDED = Clip{ .x0 = 0, .y0 = 0, .x1 = 32767, .y1 = 32767 };
};

// Row-major 1 byte/pixel glyph blit, CLIPPED to `clip` and to the framebuffer. Glyph N of an
// fw x fh font lives at N*(fw*fh) as one byte per pixel (1 = ink). Clipping is
// per pixel rather than per character: text that starts off-screen still shows
// its visible columns, and — the reason this exists — text running past the
// right edge is CUT instead of wrapping onto the next scanline (which used to
// spray window titles and icon labels across the desktop).
fn blitGlyphs(lfb: *LogicalFB, text: []const u8, x: i16, y: i16, ink: u8, paper: u8, font: []const u8, fw: i16, fh: i16, clip: Clip) void {
    const w = @min(@as(i16, @intCast(lfb.fb_w)), clip.x1);
    const h = @min(@as(i16, @intCast(lfb.fb_h)), clip.y1);
    const x_lo = @max(0, clip.x0);
    const y_lo = @max(0, clip.y0);
    const cell: usize = @intCast(fw * fh);
    for (text, 0..) |char, nb| {
        const gx = x + @as(i16, @intCast(nb)) * fw;
        if (gx >= w) return; // the rest of the string is off the right edge
        if (gx + fw <= x_lo) continue; // wholly off the left edge
        const g0 = @as(usize, char) * cell;
        var r: i16 = 0;
        while (r < fh) : (r += 1) {
            const py = y + r;
            if (py < y_lo or py >= h) continue;
            const row = @as(u32, @intCast(py)) * lfb.stride;
            var c: i16 = 0;
            while (c < fw) : (c += 1) {
                const px = gx + c;
                if (px < x_lo or px >= w) continue;
                const on = font[g0 + @as(usize, @intCast(r * fw + c))] == 1;
                lfb.fb[row + @as(u32, @intCast(px))] = if (on) ink else paper;
            }
        }
    }
}

pub const ZigOS = struct {
    background_color: Color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 },
    // View onto the shared physical framebuffer. Writing it is the out-of-ABI
    // "overscan" escape hatch (§2: memory is not sealed, only code is); the
    // sanctioned way to reach the borders is RESOLUTION + a border HBL handler.
    physical_framebuffer: *[RASTER_HEIGHT][RASTER_WIDTH]u32 = undefined,
    lfbs: [NB_PLANES]LogicalFB = undefined,
    hbl_handler: ?*const fn (*ZigOS, u16) void = null,
    system_font: []const u8 = undefined,
    system_font_6: []const u8 = undefined, // 6x6 (icon labels)
    // Mirror of the audio thread's YM2149 registers, pushed in from JS so scenes
    // can visualize the chip. 0..13 are the standard PSG registers.
    ym_regs: [16]u8 = [_]u8{0} ** 16,
    // Active audio player (0 none, 1 MOD, 2 YM, 3 sample) + per-channel scope
    // captures, both pushed in from JS for the music scene's oscilloscope.
    audio_mode: u8 = 0,
    scopes: [4][SCOPE_LEN]f32 = std.mem.zeroes([4][SCOPE_LEN]f32),
    /// Milliseconds into the playing tune — the clock a screen syncs to when
    /// its animation is written against the music rather than the frame count.
    song_ms: u32 = 0,

    // Bind the system fonts and NOTHING else — no registers, no VRAM allocation.
    //
    // For a consumer that needs to DRAW TEXT over a framebuffer somebody else
    // owns: the ROM chip does this so it can render GEM widgets for an app
    // written in C or Rust, which has no ZigOS of its own to lend. Calling the
    // full init() there would reset the machine's registers and reallocate every
    // plane out from under the running app.
    pub fn initTextOnly(self: *ZigOS) void {
        self.system_font = SYSTEM_FONT;
        self.system_font_6 = SYSTEM_FONT_6;
    }

    pub fn init(self: *ZigOS) void {
        g_base = @intCast(hw.hwVideoBase());
        Console.log("ZigOS: video hardware base @ {x}", .{g_base});

        self.physical_framebuffer = @ptrFromInt(g_base + hw.OFF_PFB);
        self.system_font = SYSTEM_FONT;
        self.system_font_6 = SYSTEM_FONT_6;
        self.hbl_handler = null;

        // default registers
        writeU8(hw.REG_RESOLUTION, hw.RES_PLANES);
        self.background_color = Color{ .r = 20, .g = 20, .b = 20, .a = 255 };
        writeU32(hw.REG_BACKGROUND, self.background_color.toRGBA());

        // Allocate each plane a normal (320×200) framebuffer from the VRAM pool.
        // A scene upgrades a plane with setOverscanBuffer() (allocates 400×280).
        vram_top = hw.OFF_VRAM;
        for (&self.lfbs, 0..) |*lfb, idx| {
            lfb.id = @intCast(idx);
            lfb.bind(vramAlloc(hw.NORMAL_FB_BYTES));
            lfb.init(self);
        }
    }

    // Reset the machine to a freshly-booted state so a DIFFERENT scene can be
    // started at runtime (the boot->cart hand-off and the effects menu use this).
    // Like init() but without re-discovering the video base, and it ALSO clears
    // the per-plane hardware mode/stride/scroll/HBL registers a previous scene
    // may have set (plain init() leaves those stale, which would corrupt the
    // next scene). Safe only after init() has run once (sets base/fonts).
    pub fn resetForScene(self: *ZigOS) void {
        self.removeHBLHandler();

        writeU8(hw.REG_RESOLUTION, hw.RES_PLANES);
        self.background_color = Color{ .r = 20, .g = 20, .b = 20, .a = 255 };
        writeU32(hw.REG_BACKGROUND, self.background_color.toRGBA());

        vram_top = hw.OFF_VRAM;
        for (&self.lfbs, 0..) |*lfb, idx| {
            lfb.id = @intCast(idx);
            writeU8(hw.REG_FB_MODE + idx, hw.FB_MODE_NORMAL);
            writeU16(hw.REG_FB_STRIDE + idx * 2, WIDTH);
            writeU16(hw.REG_HSCROLL + idx * 2, 0);
            lfb.clearFrameBufferHBLHandler();
            lfb.bind(vramAlloc(hw.NORMAL_FB_BYTES));
            lfb.init(self);
        }
    }

    // --- Features ---
    pub fn nop(self: *ZigOS) void {
        _ = self;
    }

    // Draw text in the 8x8 system font. x/y are SIGNED: GUI text can start off
    // the left/top edge (a window dragged past the border) and must be cut, not
    // wrapped onto the neighbouring scanline.
    pub fn printText(self: *ZigOS, lfb: *LogicalFB, text: []const u8, x: i16, y: i16, fg_color_index: u8, bg_color_index: u8) void {
        blitGlyphs(lfb, text, x, y, fg_color_index, bg_color_index, self.system_font, SYSTEM_FONT_WIDTH, SYSTEM_FONT_HEIGHT, Clip.UNBOUNDED);
    }

    // Draw text in the 8x8 font, confined to `clip` — for text whose glyph cell
    // has to overlap its neighbours (a menu separator's underscore sits low in
    // its cell, so the cell reaches up into the row above).
    pub fn printTextClipped(self: *ZigOS, lfb: *LogicalFB, text: []const u8, x: i16, y: i16, fg_color_index: u8, bg_color_index: u8, clip: Clip) void {
        blitGlyphs(lfb, text, x, y, fg_color_index, bg_color_index, self.system_font, SYSTEM_FONT_WIDTH, SYSTEM_FONT_HEIGHT, clip);
    }

    // Draw text in the 6x6 system font (icon labels).
    pub fn printTextSmall(self: *ZigOS, lfb: *LogicalFB, text: []const u8, x: i16, y: i16, fg_color_index: u8, bg_color_index: u8) void {
        blitGlyphs(lfb, text, x, y, fg_color_index, bg_color_index, self.system_font_6, SMALL_FONT_WIDTH, SMALL_FONT_HEIGHT, Clip.UNBOUNDED);
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
