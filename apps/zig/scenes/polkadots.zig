// --------------------------------------------------------------------------
// POLKA DOTS — the halftone torus of CODEF screen 81 (wab.com), by Antoine
// Santo / NoNameNo, MIT. Reference kept at prototypes/codef/81/.
//
// SCOPE. The torus and nothing else, by request. The original screen also
// carries a logo, a starfield, a tweened block of letters, a bouncing bubble,
// two scrolling raster strips (screen.js:113-155) and 4MAT's ProTracker module
// "carvup-2" (screen.js:30); none of that is here. The torus gets the plain
// black field the original fills first (screen.js:105), and the screen is
// silent. There is no depacker intro on this screen to skip.
//
// WHAT IT DOES. A flat-shaded torus is rendered into a TINY offscreen canvas,
// then each of that canvas's pixels is read back and stamped onto the real
// screen as one of TEN 7x7 dots, chosen by the pixel's red value. Dot size is
// the intensity. screen.js:126-132:
//
//     var imgPixels = mycanvaspetit.contex.getImageData(0, 0, 71, 48);
//     for (y...48) for (x...71) {
//         var shit = Math.floor(imgPixels.data[i] * 0.0392156862745);
//         if (imgPixels.data[i] != 0) pat.drawTile(mycanvas, shit, x*7+71, y*7+72+70);
//     }
//
// GEOMETRY — the 2x is NOT in the art. pat.png's dots have single-pixel
// features (tile 1 is one pixel, tile 2 a five-pixel plus), so the tiles are
// native 1x and halving them would destroy them. The 7 px cell pitch is
// therefore kept exactly, and it is the GRID that is resized to the machine's
// screen: 45 x 28 cells = 315 x 196, centred on 320x200. Because the
// projection's vertical field of view does not depend on the canvas size, the
// torus still fills the same fraction of the screen's HEIGHT as it does of the
// original's (75%, measured over a full revolution); only the horizontal
// margin follows the wider screen. No borders are needed and none are opened.
//
// ONE PLANE, 12 colours: the black field, the tiles' own (7,7,7) and the ten
// dot inks. The original draws everything onto one canvas; so does this.
//
// COST (measured, apps/polkadots_headless.mjs): see the harness output. The
// per-cell stamp is a real hardware BLIT, ~440 of them a frame at the torus's
// widest. That number is the argument in the blitter proposal.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const c3 = zg.zig3d;

const torus = @import("polkadots/torus.zig");
const shade = @import("polkadots/shade.zig");
const dots = @import("polkadots/dots.zig");

const PLANE = 0;

// go(): the group turns before every draw (screen.js:110-111).
const STEP_X: f64 = 0.02;
const STEP_Y: f64 = 0.04;

// Scratch the Demo struct must not carry: cart statics cost a data segment
// either way, but they keep the zero-initialised struct small.
var geometry: torus.Geometry = undefined;
var screen_buf: [torus.VERTS]c3.Screen = undefined;
var poly_buf: [torus.FACES]c3.Poly = undefined;
var grid: shade.Grid = undefined;
var palette_scratch: [256]Color = undefined;

pub const Demo = struct {
    lens: c3.Lens,
    mesh: c3.Mesh,
    blitter: zg.Blitter,
    rotation: c3.Vec3,
    blits: u32, // last frame's stamp count, for the harness

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.rotation = .{ .x = 0, .y = 0, .z = 0 };
        self.blits = 0;
        self.blitter.init();
        self.mesh = geometry.build();
        shade.setNormals(&geometry.normals);
        self.lens = c3.Lens.init(shade.CELLS_X, shade.CELLS_Y, shade.FOV, shade.NEAR, shade.FAR);

        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        palette_scratch = dots.palette();
        fb.setPalette(palette_scratch);
        fb.clearFrameBuffer(0);
    }

    /// The original is frame-locked (requestAnimFrame), and the increments are
    /// per FRAME, not per second — so the turn belongs in render(), with the
    /// draw it precedes, rather than being scaled by dt here.
    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = zigos;
        _ = dt;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[PLANE];
        self.rotation.x += STEP_X;
        self.rotation.y += STEP_Y;
        shade.render(&self.lens, &self.mesh, self.rotation, &screen_buf, &poly_buf, &grid);
        self.blitter.clear(fb, 0);
        self.blits = dots.stamp(fb, &self.blitter, &grid);
    }
};
