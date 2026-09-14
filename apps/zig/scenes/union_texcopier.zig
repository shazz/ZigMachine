// --------------------------------------------------------------------------
// The Union Demo (1989), door "COPIER TEX": TEX's copy program with rasters and
// muzak, ported from shazz's melonJS "Union Demo HTML5 Remake" 0.9.8
// (screens/texcopier/screen.js, loader.js). Program by 6719 and Mad Max, graphix
// by ES, music by Mad Max after Maniacs of Noise (Jeroen Tel): all The Union's.
//
// On screen, in draw order (screen.js:212-242), one plane, one palette:
//   black; from frame 104, six raster windows at fixed rows, each scrolling
//   through one of 8 raster images at 2.5 canvas rows a frame (draw.zig);
//   the copier's display panel;
//   a line of text whose letters are holes in a black font, a 1280-wide colour
//   texture scrolling half a canvas pixel a frame behind them. Every 7 seconds
//   the line fades out colour by colour and the next fades in; Space fades it
//   out for good and the orange "PLEASE INSERT WRT-PROTECTED SOURCE-DISK" fades
//   in (copier.zig). The remake's copy[1..6] and its LEDs are never drawn.
//
// Geometry: 640x400 canvas = ST 320x200 doubled; the ST pixel (X,Y) is canvas
// pixel (2X,2Y), with Chrome's bilinear mixes at the half-pixel draws kept as
// palette entries (assets.zig).
//
// Loading: the remake's TEX loader panel (loader.js) is the REAL depack here:
// texcopier.bin ships ZX0-packed with fx = tex_loader and that panel. Its "PRESS
// SPACE TO ENTER" wait is not kept: the screen starts when the data is in.
//
// Leaving: Escape or O (screen.js:194, 'exit' / 'O') goes back to the hub, as
// me.state.change(MENU_LOADER) does. Space ('enter') starts the copy.
// The remake's texcopier never reads jsApp.mainscrollerPos, so no return note is used.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const hw = @import("hardware");
const ZigOS = zg.ZigOS;
const blit = zg.blit;
const DepackFx = @import("depackers").depack_fx.Runner(zg, null);
const packed_assets = @import("packed_assets");

const A = @import("union_texcopier/assets.zig");
const draw = @import("union_texcopier/draw.zig");
const Copier = @import("union_texcopier/copier.zig").Copier;

// The remake plays data/music/copier.ym, "UNION DEMO Copier / Mad Max (composed
// by M.O.N.)": Mad Max's Union Demo conversion of Scoop "That's The Way It Is".
// Subtune 2 is the copier's: its FRMS tag is 21,698 frames, the dump's 21,696
// (subtune 1 is 2,306).
const MUSIC = "union/scoop.sndh";
const MUSIC_TUNE = 2;
const HUB = "union_demo";
// 35,584 bytes at 1 a line (280 a frame) depack in 128 frames; the remake's panel
// lands its 483rd letter at 14,510 ms, 104 frames at 140 ms a frame.
const DEPACK_BYTES_PER_LINE = 1;
const K_ESC: u32 = 0xE012;

// Module scope: the runner needs a stable address.
var depack: DepackFx = undefined;

const Phase = enum { loading, running };

pub const Demo = struct {
    phase: Phase,
    images: A.Images,
    copier: Copier,
    space: bool, // 'enter' pressed since the last update
    raster_image: usize, // the image whose colours are in RASTER_BASE..
    leave: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.phase = .loading;
        self.space = false;
        self.raster_image = A.RASTER_IMAGES; // none yet
        self.leave = false;
        self.copier.init();
        const buf = freeRam(A.TOTAL) orelse return self.abandon("no free RAM to depack into");
        if (!depack.start(zigos, packed_assets.union_texcopier, buf, DEPACK_BYTES_PER_LINE))
            return self.abandon("packed image unreadable");
        self.images = A.Images.split(buf);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.leave) return;
        if (self.phase == .loading) switch (depack.frame(zigos)) {
            .more => return,
            .done => self.start(zigos), // and this frame is the screen's first
            .failed => return self.abandon("depack failed"),
        };
        self.copier.update(self.space);
        self.space = false;
        const image = self.copier.raster_texture % A.RASTER_IMAGES;
        if (image != self.raster_image) {
            A.setRasterColours(&zigos.lfbs[0], self.images.rasters, image);
            self.raster_image = image;
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.phase != .running or self.leave) return;
        const dst = blit.Dst.plane(&zigos.lfbs[0]);
        draw.clear(dst);
        draw.rasters(dst, &self.copier);
        draw.display(dst, self.images);
        draw.textLine(dst, &self.copier, self.images);
    }

    /// Host input ids: 6 back. Fire (5) also comes with Enter, which the screen ignores.
    pub fn input(self: *Demo, dir: u8) void {
        if (dir == 6) self.leave = true;
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC or cp == 'O' or cp == 'o') self.leave = true;
        if (cp == ' ' and self.phase == .running) self.space = true;
    }

    /// me.state.change(MENU_LOADER): load the Union Demo menu's disk.
    pub fn pollCart(self: *Demo) i32 {
        return if (self.leave) 1 else 0;
    }

    pub fn cartTag(self: *Demo) []const u8 {
        _ = self;
        return HUB;
    }

    fn start(self: *Demo, zigos: *ZigOS) void {
        const fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPalette(A.palette);
        zg.requestSongTune(MUSIC, MUSIC_TUNE); // onResetEvent
        self.phase = .running;
    }

    /// Without its pictures there is no screen to show: say why and go back.
    fn abandon(self: *Demo, why: []const u8) void {
        zg.Console.log("union_texcopier: {s}, back to the menu", .{why});
        self.leave = true;
    }
};

/// `len` bytes of the cart's RAM window above its statics and stack.
fn freeRam(len: usize) ?[]u8 {
    if (hw.hwRamFree() < len) return null;
    const base: usize = hw.hwRamBase() + hw.hwRamUsed();
    return @as([*]u8, @ptrFromInt(base))[0..len];
}
