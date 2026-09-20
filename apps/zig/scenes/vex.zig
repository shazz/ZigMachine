// --------------------------------------------------------------------------
// VEX 2025 — "vEctRoniX presents Grand Theft Auto VI, Atari ST/E".
//   code SLiPPY · graphics Jade · music !Cube/Aggression · scrolltext Metallinos
//   Released at Buxton Bytes 2025 (Verbrechen im Fadenkreuz, since 1992).
//
// Ported from the ORIGINAL ST binary (VEX_2025.TOS, UPX-packed; the addresses
// in the comments are the unpacked program's own link addresses, file offset
// = address + 28).  There is no remake of this screen: every table, increment
// and coordinate below was read out of the 68000 code.
//
// What is on screen, top to bottom:
//   rows   0.. 43  Jade's chrome VECTRONIX logo, 4 planes, blitted once ($3d72)
//   rows  58..177  the 40-column credits panel in plane 2 ($33a2/$340c), the 30
//                  floating cubes in planes 0+1 ($dd2) behind it, and the big
//                  green scroller in plane 3 ($e3a0) in front of both
//   rows 191..198  Metallinos' 1-pixel-a-frame bottom scroller ($dca6)
// and behind all of it the Timer-B raster chain ($e90a): 71 splits of two
// scanlines over rows 47..188, repainting colours 4-7 from a 232-word ramp and
// 8-15 from a 71-word table, plus four rewrites of the cubes' colours 1-3.
//
// ONE PLANE.  The ST's sixteen colours collapse: 4..7 always held one value and
// 8..15 another, so a pixel is background, one of three cube shades, panel ink
// or scroller ink.  Those six entries are 16..21 here and the raster drives
// them from a per-row table; 0..15 stay the logo's own palette, which nothing
// below row 46 uses.
//
// Before any of that, the demo opens on its 320x200 "V" title picture (chrome
// ring, flame V) — a separate part of the program at $804 — which resolves out
// of white, holds, flashes back out at frame 250 and hands over at 300.  See
// vex/title.zig.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;
const Console = zg.Console;

const A = @import("vex/assets.zig");
const P = @import("vex/planes.zig");
const pal = @import("vex/palette.zig");
const Scroller = @import("vex/scroller.zig").Scroller;
const Small = @import("vex/small.zig").Small;
const Credits = @import("vex/credits.zig").Credits;
const cubes = @import("vex/cubes.zig");
const raster = @import("vex/raster.zig");
const Title = @import("vex/title.zig").Title;
const Intro = @import("vex/intro.zig");

// !Cube / Aggression's tune, ripped straight out of the intro's DATA at $3906e
// (the VBL's `jsr` lands on $39076, the SNDH play vector) — so this is the
// screen's own music, not a match. FLAG ~y, one subtune, peak 0.0493.
const MUSIC = "vex.sndh";

// The palette entries the raster drives live with the layers they colour.
const BG = P.BG;
const DRIVEN = P.DRIVEN;

pub const Demo = struct {
    // demo_main holds the cart as `undefined`: every field is set in init().
    fade: pal.Fade,
    ramp: pal.Ramp,
    scroller: Scroller,
    small: Small,
    credits: Credits,
    cubes: cubes.Cubes,
    /// $804's title screen; the intro does not start until it is done.
    title: Title,
    /// The demo's FIRST screen ($b5b8's script), ahead of the title.
    intro: Intro.Intro,
    /// $30dc4: the VBL counts 100 frames before it lets any effect run, and
    /// $e9ba gates colours 1-3 and 8-15 on the same counter.
    settle: u16,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("vex: vEctRoniX 2025 — GTA VI cracktro (SLiPPY/Jade/!Cube/Metallinos)", .{});

        const fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.clearFrameBuffer(BG);
        P.clear();

        self.fade.init();
        self.ramp.init();
        self.scroller.init();
        self.small.init();
        self.credits.init();
        self.cubes.init();
        self.settle = 100;

        self.intro.init(fb); // the script screen runs first; it starts the title
        zigos.setHBLHandler(raster.borderHbl); // colour 0 drives the border throughout
        fb.setFrameBufferHBLHandler(0, raster.preTitleHbl); // ...and the plane, while the script runs
        raster.band_top = Intro.BAND_TOP;
        raster.band_rows = Intro.BAND_ROWS;
        zg.requestSong(MUSIC); // the tune plays under the title too ($843b8)
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb: *LogicalFB = &zigos.lfbs[0];
        if (!self.intro.finished) {
            self.intro.step(fb);
            if (self.intro.finished) self.title.init(fb); // $ff -> state 2
            return;
        }
        if (!self.title.done()) {
            self.title.step();
            if (self.title.done()) self.startIntro(fb);
            return;
        }
        self.fade.step(); // $ab86
        self.ramp.advance(); // $e81e's ramp pointer
        if (self.settle > 0) {
            self.settle -= 1;
            return;
        }
        self.scroller.update(); // $e3a0
        self.scroller.draw(); // $e602
        self.small.update(); // $dca6
        self.credits.update(); // $dece / $df02
        self.cubes.fadeColours(); // $b78e -> $d24
        self.cubes.draw(); // $dd2
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb: *LogicalFB = &zigos.lfbs[0];
        if (!self.intro.finished) {
            // $b412/$b45c split colour 0: the cleared band is black and
            // everything outside it -- screen AND border -- is white. That
            // white is constant; op 2's flag records the $16cb6 write at the
            // end of the script but does not change what is drawn here.
            fb.palette[Intro.INK] = pal.rgba(self.intro.ink);
            raster.band_in = pal.rgba(0x000);
            raster.band_out = pal.rgba(0x777);
            return;
        }
        if (!self.title.done()) {
            self.title.publish(fb);
            raster.band_top = 0;
            raster.band_rows = zg.HEIGHT; // one flat band: the picture's colour 0
            raster.band_in = pal.rgba(self.title.live[0]);
            raster.band_out = raster.band_in;
            fb.fb_hbl_handler = null; // the picture owns all 16 colours
            return;
        }
        // A BOUNDED view of the plane: fb.fb is a many-pointer, so slicing it
        // by hand would silence every bounds check on the recompose.
        const pixels = fb.fb[0 .. @as(usize, fb.stride) * fb.fb_h];
        self.publishPalette(fb);
        self.buildRasterRows();
        P.composeBand(pixels, fb.stride);
        P.composeSmall(pixels, fb.stride);
    }

    /// $12c: the title is over. Clear it away, put the logo up and let the
    /// Timer-B chain start driving the six raster entries.
    fn startIntro(self: *Demo, fb: *LogicalFB) void {
        fb.clearFrameBuffer(BG);
        P.clear();
        drawLogo(fb);
        self.publishPalette(fb);
        fb.setFrameBufferHBLHandler(0, raster.rasterHbl);
        raster.band_rows = 0; // back to the Timer-B table
    }

    /// The VBL blasts the 16-word palette then overrides colour 0 with $31310.
    fn publishPalette(self: *const Demo, fb: *LogicalFB) void {
        for (0..16) |i| fb.palette[i] = pal.rgba(self.fade.live[i]);
        fb.palette[0] = pal.rgba(self.fade.live[pal.TOP_BG]);
    }

    fn buildRasterRows(self: *const Demo) void {
        const top = pal.rgba(self.fade.live[pal.TOP_BG]);
        const flash = pal.rgba(self.fade.live[pal.SPLIT_BG]);
        const body = pal.rgba(self.fade.live[pal.BODY_BG]);
        const small_ink = pal.rgba(self.fade.live[pal.SMALL_INK]);
        var b: usize = 0;
        for (&raster.row_pal, 0..) |*row, y| {
            const s = raster.splitOf(y);
            row[0] = if (y < raster.SPLIT_TOP or y >= P.SMALL_TOP) top else if (y < raster.SPLIT_TOP + 2 or y >= raster.SPLIT_END) flash else body;
            while (b + 1 < cubes.BAND_ROW.len and y >= cubes.BAND_ROW[b + 1]) b += 1;
            const shades = self.cubes.band(if (self.settle > 0) 0 else b, &self.fade);
            for (shades, 0..) |c, i| row[1 + i] = pal.rgba(c);
            row[4] = if (y >= P.SMALL_TOP) small_ink else pal.rgba(self.ramp.colour(s));
            row[5] = pal.rgba(if (self.settle > 0) self.fade.live[8] else A.be(A.scrollcol_b, s));
        }
    }
};

fn drawLogo(fb: *LogicalFB) void {
    for (0..A.LOGO_H) |y| {
        const src = A.logo[y * zg.WIDTH ..][0..zg.WIDTH];
        @memcpy(fb.fb[y * fb.stride ..][0..zg.WIDTH], src);
    }
}
