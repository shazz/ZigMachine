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
// FOUR RENDER MODES, ONE GRID. Keys 1..4 (or Space) switch only the RENDERER;
// the CPU half — torus.zig projecting and shade.zig reducing — is identical for
// all of them, which is the split the example exists to teach. Every mode
// drives the real blitter, and the bottom line reports the operations it issued
// and the pixels it touched, because the cost is half of the comparison:
//
//   1 DOT SIZE   one BLIT per lit cell from a ten-dot sheet (dots.zig)
//   2 HALFTONE   one FILL per RUN, shaded by the HALFTONE register
//   3 SOLID      one FILL per run, shaded by the palette — the baseline
//   4 FILL DOTS  one FILL per lit cell, a square sized by the intensity
//
// Escape leaves. Declaring key() takes Escape away from the host, so this
// scene sets wants_quit itself.
//
// COST (apps/polkadots_headless.mjs, averaged over 40 interleaved rounds on the
// same torus): 223 / 99 / 123 / 173 blitter operations a frame, all four at
// ~0.3 ms in the cart. The halftone register covers the grid in less than half
// the operations of the dot sheet because a RUN of equal cells is one fill —
// and it cannot vary the dot. That trade is what the screen is for.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const c3 = zg.zig3d;

const torus = @import("polkadots/torus.zig");
const shade = @import("polkadots/shade.zig");
const dots = @import("polkadots/dots.zig");
const modes = @import("polkadots/modes.zig");
const readout = @import("polkadots/readout.zig");

const PLANE = 0;
const K_ESC: u32 = 0xE012;
const DIR_FIRE = 5; // the host maps Space and Enter to input(5)

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
    mode: modes.Mode,
    cost: dots.Cost, // last frame's blitter operations, for the label and the tap
    loads: u32, // halftone pattern changes, mode 2 only
    wants_quit: bool, // demo_main returns to the menu on this

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.rotation = .{ .x = 0, .y = 0, .z = 0 };
        self.mode = .dot_size;
        self.cost = .{};
        self.loads = 0;
        self.wants_quit = false;
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

    /// 1..4 pick the renderer, Space cycles, Escape leaves. A screen that
    /// declares key() owns every key, Escape included.
    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC) self.wants_quit = true;
        if (cp >= '1' and cp <= '0' + modes.NAMES.len) self.mode = @enumFromInt(cp - '1');
    }

    pub fn input(self: *Demo, dir: u8) void {
        if (dir == DIR_FIRE) self.mode = @enumFromInt((@intFromEnum(self.mode) + 1) % modes.NAMES.len);
    }

    /// The host can drive the mode too (the headless harness does), so the four
    /// renderers can be compared without a keyboard.
    pub fn setShadeMode(self: *Demo, m: u32) void {
        if (m < modes.NAMES.len) self.mode = @enumFromInt(m);
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[PLANE];
        self.rotation.x += STEP_X;
        self.rotation.y += STEP_Y;
        shade.render(&self.lens, &self.mesh, self.rotation, &screen_buf, &poly_buf, &grid);
        // The clear is a FILL like any other, so the halftone pattern mode 2
        // left loaded would dither it. Drop it before clearing, every frame.
        self.blitter.clearHalftone();
        self.blitter.clear(fb, 0);
        self.loads = 0;
        self.cost = switch (self.mode) {
            .dot_size => dots.stamp(fb, &self.blitter, &grid),
            .halftone => modes.halftone(fb, &self.blitter, &grid, &self.loads),
            .solid => modes.solid(fb, &self.blitter, &grid),
            .fill_dots => modes.fillDots(fb, &self.blitter, &grid),
        };
        const m = @intFromEnum(self.mode);
        readout.label(zigos, fb, m, modes.NAMES[m], self.cost.ops, self.cost.px);
        readout.tap(fb, m, self.cost.ops);
    }
};
