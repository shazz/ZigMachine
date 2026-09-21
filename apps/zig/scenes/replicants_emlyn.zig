// --------------------------------------------------------------------------
// THE REPLICANTS — "Emlyn Hughes International Soccer" crack intro.
// Coding -VICKERS-, Amiga font ripped by -VANTAGE- of ST CONNEXION, the big
// REPLICANTS logo by -PULSAR- of NEXT, music by -MAD MAX- of TEX; the
// scrolltext is theirs word for word.
//
// Ported from the CODEF HTML5 remake (wab.com screen 17, MIT), kept at
// prototypes/codef/17/. Assets: tools/private_tools/replicants_emlyn_assets.py.
// init() goes straight to go(): there is no depacker intro to skip.
//
// The remake canvas is 640x480 = ST 320x240 doubled, and go() fills all of it,
// so this ST screen ran with a border open. The 320x240 content sits at (40,20)
// in the 400x280 overscan plane, borders opened with the res-flicker trick.
//
// go() (screen.js:94-115), in its own order, once a frame:
//   canvas.fill('#000000')
//   group.rotation.x += 0.04, then my3d.draw()      12 bars (emlyn/balls.zig)
//   logo.draw(320 + posx, 300 + sin(posy)*300)      mid-handled, 2190x314 ST
//   scrolltext.draw(390)                            flat, speed 4
//   then posx steps +-32 between +-1920 and posy += 0.02
// Note the logo moves AFTER it is drawn while the rotation moves before, so the
// first frame shows rotation 0.04 at logo position (0, 0). update() keeps that.
//
// TWO DELIBERATE DIVERGENCES FROM THE REMAKE (Matt, and the point of them is
// that the remake is the deficient artefact here):
//
//  1. The bars are REAL RASTERS, borders included. The remake blits bar.png as
//     a sprite; the ST screen changed the palette per scanline, which is what
//     bar.png's 64 one-colour rows were always a table FOR. So the background is
//     a ramp of palette indices across all 400 raster columns and the plane's
//     HBL colours them per line (emlyn/rasters.zig). Nothing of the bars is in
//     the framebuffer, and every border is open so they run edge to edge. The
//     LOGO and the SCROLLTEXT are drawn to the whole 400x280 raster for the
//     same reason: on a fullscreen screen there is no edge to stop at.
//  2. SPACE switches between ORIGINAL (the faithful screen 17) and ZIG, where
//     the bars turn through every direction AND the scrolltext bends on CODEF
//     484's middle-scroller curve (emlyn/scroller.zig), the one picked out of
//     the distortion lab. Both grow in and flatten out over the same 20 frames.
//
// ONE plane, one palette: 107 entries of art (unquantized) + up to 149 raster
// buckets. Per frame: a colour table, a 400-byte pattern per plane row, one
// clipped logo blit and 12 glyphs.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const hw = @import("hardware");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const blit = zg.blit;
const c3 = zg.zig3d;
const zx0 = @import("depackers").zx0;
const packed_assets = @import("packed_assets");

const A = @import("replicants_emlyn/assets.zig");
const balls = @import("replicants_emlyn/balls.zig");
const rasters = @import("replicants_emlyn/rasters.zig");
const Mode = @import("replicants_emlyn/mode.zig").Mode;
const Logo = @import("replicants_emlyn/logo.zig").Logo;
const Scroller = @import("replicants_emlyn/scroller.zig").Scroller;

// The tune is Mad Max's, and the remake plays it as screens/017/zic.ym, a YM
// register dump. This project ships SNDH only, so the dump was matched against
// the archive: zic.ym is LHA-packed and unpacks to SEVEN7.YM, whose YM5 header
// names itself -- "7 Gates of Jambala Level 5" / "Jochen Hippel" (= Mad Max).
// The cracktro simply reused a Hippel GAME tune; nothing here is Emlyn Hughes
// music, and the archive's "Emlyn Hughes Football" (David Whittaker) scores
// 19% against the dump.
//
// Proved by YM register match, not by name: subtune 9 played from its start is
// bit-identical to the dump over all 6784 frames (135.7 s) -- 88192/88192
// registers, zero mismatches, offset 0. Best rival subtune is 49%, which is
// just the noise floor of held/silent registers. The YM title says "Level 5"
// but the SNDH's own ordering puts it at 9; trust the measurement.
// Take the un-flagged file, NOT Mad_Max/Games/SID/ -- that one is ~abdy
// (STE DMA), which loads fine here and plays SILENCE.
const MUSIC = "seven_gates_of_jambala.sndh";
const MUSIC_TUNE: u8 = 9;

const PLANE = 0;
const DIR_FIRE = 5; // the host maps Space AND Enter to input(5)

pub const Demo = struct {
    ok: bool,
    images: A.Images,
    logo: Logo,
    scroller: Scroller,
    particles: [balls.POINTS.len]c3.Particle,
    started: bool, // go() has drawn once, so the logo may move
    rotation_x: f64, // group.rotation.x
    mode: Mode, // ORIGINAL or ZIG, and how far between (emlyn/mode.zig)

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.ok = false;
        self.started = false;
        self.rotation_x = 0;
        self.mode.init();
        self.logo.init();
        self.scroller.init();
        self.particles = undefined;
        balls.init();

        const buf = freeRam(A.TOTAL) orelse return fail("no free RAM for the assets");
        if (zx0.depack(packed_assets.replicants_emlyn, buf) == null) return fail("depack failed");
        self.images = A.Images.split(buf);

        // The ST's border is colour 0; black here, so the closed side borders
        // meet the open top and bottom ones.
        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.setPalette(A.palette);
        fb.setPaletteEntry(A.TRANSPARENT, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.openBorders(.all); // a raster runs edge to edge, so every border opens
        rasters.install(fb); // ... and takes over its HBL, flicker included
        fb.clearFrameBuffer(A.BLACK); // until render() paints the ramp over it
        zg.requestSongTune(MUSIC, MUSIC_TUNE);
        self.ok = true;
    }

    /// No key() and no ownsKeyboard() on purpose: the host maps Space to
    /// input(5) for a cart that does not own the keyboard, and keeps its own
    /// Escape -> menu (demo_main.zig). Declaring key() here would take Escape
    /// away with it and strand the screen.
    pub fn input(self: *Demo, dir: u8) void {
        if (dir == DIR_FIRE) self.mode.toggle();
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        if (!self.ok) return;
        self.rotation_x += balls.ROT_STEP; // go() turns the group before drawing
        self.scroller.update();
        if (self.started) self.logo.move(); // ... and moves the logo after
        self.started = true;
        self.mode.update();
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (!self.ok) return;
        // my3d.draw(), split in two: the projection is still three.js's, but
        // what it feeds is the HBL's colour table, not a blit.
        rasters.build(balls.project(self.rotation_x, &self.particles), self.mode.theta);
        const plane = blit.Dst.plane(&zigos.lfbs[PLANE]);
        for (0..plane.h) |y| @memcpy(plane.buf[y * plane.stride ..][0..rasters.row.len], &rasters.row);
        // Rasters, then the logo, then the scrolltext — the remake's order.
        // All three take the WHOLE raster now: nothing stops at an edge this
        // screen no longer has.
        self.logo.draw(plane, self.images.logo);
        self.scroller.draw(plane, self.images.font, self.mode.bend);
    }
};

fn fail(why: []const u8) void {
    zg.Console.log("replicants_emlyn: {s}", .{why});
}

/// `len` bytes of the cart's RAM window above its statics and stack.
/// check_fits cannot see this: the 752 KB the assets depack into are borrowed
/// at run time, and packing shrank the static footprint the gate DOES measure,
/// so the free-RAM figure it prints is larger than the truth by that much.
fn freeRam(len: usize) ?[]u8 {
    if (hw.hwRamFree() < len) return null;
    const base: usize = hw.hwRamBase() + hw.hwRamUsed();
    return @as([*]u8, @ptrFromInt(base))[0..len];
}
