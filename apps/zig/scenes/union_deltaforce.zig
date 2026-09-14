// --------------------------------------------------------------------------
// The Union Demo (1989), DELTA FORCE: the "Sphericool" screen, ported from
// shazz's melonJS "Union Demo HTML5 Remake" 0.9.8 (screens/deltaforce/
// screen.js, loader.js). Program by New Mode, graphics by Slime and Questlord,
// bubbles by ES, "Mega Apocalypse" by Mad Max after Rob Hubbard: The Union's.
//
// On screen, in draw order (screen.js:320-434), one plane, one palette:
//   the floor slab; the two Delta Force logos, squashed flat to swap
//   (stage.zig); three balls jumping on YM volume changes;
//   the scroller, turned by cos(twist) under its effect letters (scroller.zig);
//   the sine-waved credits band sliding its words in (intro.zig).
// Both texts are coloured by the gold backdrop scrolling 6 px a frame (band.zig).
//
// Geometry: a 640x400 canvas = ST 320x200 doubled; everything halves into
// 320x200 (the scroller band's canvas rows 400-409 are cut there too).
//
// DELIBERATE DEVIATION (Matt, 2026-09-14): the screen loops. At the end of the
// scrolltext its 'g' restarts the credits band, but screen.js resets neither
// the band's speed nor the effect nor the letter ring: in the remake the band
// then starts at its other end, and each time it reaches its last word the
// still-selected RESET restarts it again, so the scroller never runs a second
// time. Here RESET also restores introScrollSpeed (14), fx (REVERSE) and the
// scrolltext's initial ring, so every cycle is the first one (about 14,250
// frames). Every other number is screen.js's.
//
// Loading: the remake's TEX loader panel (loader.js) is the REAL depack: the
// screen's pictures ship ZX0-packed with fx = tex_loader and that panel. The
// "PRESS SPACE TO ENTER" wait is not kept: the screen starts when the data is in.
//
// Keys: Escape or Space leave for the hub (screen.js:275-279); '0' skips the
// credits band (310). The remake's 1-7 scroll speeds last only while a key is
// held (draw() sets the speed back to 10 every frame), so they are not ported.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const hw = @import("hardware");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const blit = zg.blit;
const DepackFx = @import("depackers").depack_fx.Runner(zg, null);
const packed_assets = @import("packed_assets");

const A = @import("union_deltaforce/assets.zig");
const stage = @import("union_deltaforce/stage.zig");
const Band = @import("union_deltaforce/band.zig").Band;
const Intro = @import("union_deltaforce/intro.zig").Intro;
const Scroller = @import("union_deltaforce/scroller.zig").Scroller;

// jsApp.YMPlayer.fetchFile("data/music/MegaApocalypse.ym"): the same tune as
// Mad Max's own SNDH (Union_Demo/Mega_Apocalypse.sndh, FLAG ~y, one subtune).
const MUSIC = "union/mega_apocalypse.sndh";
const HUB = "union_demo";
// 186,774 bytes at 7 a line (1,960 a frame) depack in 96 frames, about the 94
// (13,130 ms at 140 ms a frame) the remake's 437-letter panel takes.
const DEPACK_BYTES_PER_LINE = 7;
const K_ESC: u32 = 0xE012;
const INTRO_W = 640; // introcanvas 1280 wide, halved
const SCROLL_W = 320; // scrollcanvas 640 wide, halved
const GOLD_STEP = 6; // goldY += 6; if (goldY >= 118) goldY = 0
const GOLD_WRAP = 118;

// Module scope: the runner needs a stable address.
var depack: DepackFx = undefined;

const Phase = enum { loading, running, failed };

pub const Demo = struct {
    phase: Phase,
    images: A.Images,
    logo: stage.Logo,
    voices: stage.Voices,
    gold_y: u32,
    intro: Intro,
    scroller: Scroller,
    intro_band: Band,
    scroll_band: Band,
    skip_intro: bool,
    leave: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.phase = .failed;
        self.skip_intro = false;
        self.leave = false;
        self.gold_y = 0;
        self.logo.init();
        self.voices.init();
        self.intro.init();
        self.scroller.init();
        const intro_len = Band.bytes(INTRO_W);
        const buf = freeRam(A.TOTAL + intro_len + Band.bytes(SCROLL_W)) orelse return fail("no free RAM to depack into");
        const data = buf[0..A.TOTAL];
        self.intro_band = Band.init(buf[A.TOTAL..][0..intro_len], INTRO_W);
        self.scroll_band = Band.init(buf[A.TOTAL + intro_len ..], SCROLL_W);
        if (!depack.start(zigos, packed_assets.union_deltaforce, data, DEPACK_BYTES_PER_LINE))
            return fail("packed image unreadable");
        self.images = A.Images.split(data);
        self.phase = .loading;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.phase == .loading) switch (depack.frame(zigos)) {
            .more => return,
            .done => self.start(zigos), // and this frame is the screen's first
            .failed => {
                self.phase = .failed;
                return fail("depack failed");
            },
        };
        if (self.phase != .running) return;
        // update(), screen.js:143-311
        self.logo.update();
        self.gold_y += GOLD_STEP;
        if (self.gold_y >= GOLD_WRAP) self.gold_y = 0;
        self.voices.update(&zigos.ym_regs);
        self.intro.update();
        if (self.intro.part != .intro_only) self.scroller.takeMarker();
        if (self.skip_intro) self.intro.part = .outro;
        self.skip_intro = false;
        // draw()'s own state changes, in its order: the scroller's effect can
        // restart the credits band before the band is drawn.
        self.scroller.visible = false;
        if (self.intro.part != .intro_only and self.scroller.advance()) self.intro.restart();
        self.intro.advance();
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.phase != .running) return;
        const dst = blit.Dst.plane(&zigos.lfbs[0]);
        @memset(dst.buf, A.BLACK); // maincanvas.fill('#000000')
        stage.draw(dst, &self.images, &self.logo, &self.voices);
        self.scroller.draw(dst, &self.scroll_band, &self.images, self.gold_y);
        self.intro.draw(dst, &self.intro_band, &self.images, self.gold_y, self.scroller.twist);
    }

    /// Host input ids: 5 fire, 6 back.
    pub fn input(self: *Demo, dir: u8) void {
        if (dir == 6 or (dir == 5 and self.phase == .running)) self.leave = true;
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC or (cp == ' ' and self.phase == .running)) self.leave = true;
        if (cp == '0' and self.phase == .running) self.skip_intro = true;
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
        const fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPalette(A.palette);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        zg.requestSong(MUSIC); // onResetEvent
        self.phase = .running;
    }
};

fn fail(why: []const u8) void {
    zg.Console.log("union_deltaforce: {s}", .{why});
}

/// `len` bytes of the cart's RAM window above its statics and stack.
fn freeRam(len: usize) ?[]u8 {
    if (hw.hwRamFree() < len) return null;
    const base: usize = hw.hwRamBase() + hw.hwRamUsed();
    return @as([*]u8, @ptrFromInt(base))[0..len];
}
