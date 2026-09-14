// --------------------------------------------------------------------------
// The Union Demo (1989), TCB2: The Carebears' "WOW!-SCROLLER", ported from
// shazz's melonJS "Union Demo HTML5 Remake" 0.9.8 (screens/superscroller/
// screen.js, loader.js). Program by Nick and Jas, graphics by ES, sampled
// sound by An Cool: all The Carebears' / The Union's.
//
// On screen, in draw order (screen.js:106-138), one plane:
//   back.png, three copies 398 canvas rows apart, scrolling up 3.35 a frame
//   the scroller: 384x380 letters, 7 px a frame, coloured 'source-atop' by five
//     copies of rasters.png scrolling up 2 a frame, at canvas y 14
//   overlay.png, two copies riding with the back
//
// Geometry: a 640x400 canvas = ST 320x200 doubled; ST pixel (x, y) is canvas
// pixel (2x, 2y), so nothing needs the borders.
//
// The fractional scroll is the look. Chrome does not snap 3.35 px: it filters
// (chrome_draw.zig, measured on the remake's own frames), so the rows of the
// back and overlay blend in 16ths while they move. Those blends are exact per
// line through a line palette (linepal.zig): 80 entries a line, 56 the most any
// line needs. The JS replay of screen.js with that filtering matches Chrome at
// 0 px on 29 frames (apps/union_superscroller_replay.mjs).
//
// Loading: the remake's TEX loader panel (loader.js) is the real depack here:
// superscroller.bin ships ZX0-packed with fx = tex_loader and that panel. The
// "PRESS SPACE TO ENTER" wait is not kept: the screen starts when the data is in.
//
// Leaving: Escape or Space ('exit' / 'enter', screen.js:93-97) goes back to the
// hub, as me.state.change(MENU_LOADER) does. The remake starts the text where
// the menu's scroller stood (jsApp.mainscrollerPos); a separate cart cannot
// know that, so it starts at the beginning.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const hw = @import("hardware");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const DepackFx = @import("depackers").depack_fx.Runner(zg, null);
const packed_assets = @import("packed_assets");

const A = @import("union_superscroller/assets.zig");
const Motion = @import("union_superscroller/motion.zig").Motion;
const compose = @import("union_superscroller/compose.zig");

// me.audio.playTrack("zik_tcb2") (screen.js:67): data/music/zik_tcb2.ogg, An
// Cool's sampled sound (loader.js:28-29 credits it). The Union_Demo folder of
// the SNDH archive has no TCB2 tune; this is AN_Cool/Wow_Scroller.sndh ("Wow
// Scroller", AN Cool, 1989, one subtune, FLAG ~ay: its samples go through the
// YM's volume registers, so it plays here).
const MUSIC = "union/wow_scroller.sndh";
const HUB = "union_demo";
// 140,601 bytes at 5 a line (1,400 a frame) depack in 101 frames; the remake's
// panel lands its 437th letter after 94 (13,130 ms at 140 ms a frame).
const DEPACK_BYTES_PER_LINE = 5;
const K_ESC: u32 = 0xE012;

// Module scope: the runner needs a stable address.
var depack: DepackFx = undefined;

const Phase = enum { loading, running, left };

pub const Demo = struct {
    phase: Phase,
    buf: []u8,
    images: A.Images,
    motion: Motion,
    /// 200 lines x 80 colours: in free RAM after the depacked image, not in the cart's data.
    palette: *compose.Palette,
    leave: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.phase = .left;
        self.buf = &.{};
        self.images = undefined;
        self.leave = false;
        self.motion.init();
        const pal_at = std.mem.alignForward(usize, A.TOTAL, @alignOf(compose.Palette));
        const ram = freeRam(pal_at + @sizeOf(compose.Palette)) orelse return self.abandon("no free RAM to depack into");
        self.buf = ram[0..A.TOTAL];
        self.palette = @ptrCast(@alignCast(ram[pal_at..].ptr));
        self.palette.init();
        if (!depack.start(zigos, packed_assets.union_superscroller, self.buf, DEPACK_BYTES_PER_LINE))
            return self.abandon("packed image unreadable");
        self.phase = .loading;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.phase == .loading) switch (depack.frame(zigos)) {
            .more => return,
            .done => self.start(zigos), // and this frame is the screen's first
            .failed => return self.abandon("depack failed"),
        };
        if (self.phase != .running) return;
        self.motion.step();
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.phase != .running) return;
        compose.drawFrame(zg.blit.Dst.plane(&zigos.lfbs[0]), &self.images, &self.motion, self.palette);
    }

    /// Host input ids: 5 fire, 6 back.
    pub fn input(self: *Demo, dir: u8) void {
        if (dir == 6 or (dir == 5 and self.phase == .running)) self.leave = true;
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC or (cp == ' ' and self.phase == .running)) self.leave = true;
    }

    pub fn pollCart(self: *Demo) i32 {
        if (!self.leave) return 0;
        self.leave = false;
        return 1;
    }

    pub fn cartTag(self: *Demo) []const u8 {
        _ = self;
        return HUB;
    }

    fn start(self: *Demo, zigos: *ZigOS) void {
        self.images = A.Images.split(self.buf);
        const fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        self.palette.install(fb);
        zg.requestSong(MUSIC); // onResetEvent
        self.phase = .running;
    }

    /// Without its pictures there is no screen: say why and go back to the hub.
    fn abandon(self: *Demo, why: []const u8) void {
        zg.Console.log("union_superscroller: {s}, back to the menu", .{why});
        self.phase = .left;
        self.leave = true;
    }
};

/// `len` bytes of the cart's RAM window above its statics and stack, starting
/// on an 8-byte boundary so the palette's u32 tables can live in it.
fn freeRam(len: usize) ?[]u8 {
    const used: usize = hw.hwRamBase() + hw.hwRamUsed();
    const base = std.mem.alignForward(usize, used, 8);
    if (hw.hwRamFree() < base - used + len) return null;
    return @as([*]u8, @ptrFromInt(base))[0..len];
}
