// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const zg = @import("zigos");
const readI16Array = zg.readI16Array;
const convertU8ArraytoColors = zg.convertU8ArraytoColors;

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;


const Scrolltext = zg.Scrolltext;
const za = zg.za;
const shapes = zg.shapes;
const Coord = shapes.Coord;


// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = zg.HEIGHT;
const WIDTH: u16 = zg.WIDTH;

// music — the screen's own tune, played by its own 68000 (docs/music/).
// AN Cool's own "AN Bass" from the So Watt demo (1989) — the demo this very
// cracktro's scrolltext announces. NOT the So Watt loader tune: that one is
// flagged ~a (STE DMA samples), which the SNDH player does not emulate — it
// loads and plays silence.
const MUSIC = "sowatt_an_bass.sndh";

// scrolltext
pub const NB_FONTS: u8 = 11;
const fonts_b = @embedFile("../assets/screens/ancool/fonts_pal.raw");
const SCROLL_TEXT = "                       YO YO   -AN COOL- IS BACK TO BURN WITH A NEW CRACK........ AND THE NEW CRACK IS               THE GAMES......    THIS TIME -MEGA CRIBB- FROM -1 LIFE CREW- SITS BY MY SIDE AND EATS CANDY   THE INTRO IS MADE BY: -AN COOL- AND THE CRACKING IS MADE BY: -AN COOL- AND -MEGA CRIBB-          BELIVE IT OR NOT, THE MUSAXX IS MADE BY: -AN COOL-           THIS GAME IS THE BEST SPORT-GAME I'VE SEEN ON THE ATARI ST AND I HOPE YOU WILL HAVE A GREAT TIME PLAYING IT.          I'VE BEEN OF THE CRACKING MARKET FOR A WHILE, BUT IT'S BECAUSE OF THE NEW DEMO (SOWHAT) WE ARE CODING. THE DEMO WILL CONTAIN ABOUT 10 SCREENS AND ALMOST ALL IS GOOD (I THINK)...   YOU WILL SEE MORE 2D-OBJECTS AND MORE COMPLEX 2D-OBJECTS IN THE DEMO-LOADER. THE DEMO SHOULD HAVE BEEN RELEASED AT OUR COPYPARTY THE 3-6 AUG. BUT AS ALWAYS........  YEAH, YOU KNOW??????.........        A HELLO GOES TO NICK OF TCB (HE WORKS AS A SECRET AGENT FOR KREML NOW)  AND SNAKE THE  LITTLE YELLOW BIRD OF REPLICANTS.......        OK.  I THINK THAT THAT WAS ALL FOR THIS TIME.....................";
const SCROLL_CHAR_WIDTH = 32; 
const SCROLL_CHAR_HEIGHT = 17;
const SCROLL_SPEED = 4;
const SCROLL_CHARS = " ! #$%&'()*+,-./0123456789:;<=>? ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const g_y_offset_table_b = readI16Array(@embedFile("../assets/screens/ancool/scroller_sin.dat"));

// palettes
const font_pal = convertU8ArraytoColors(@embedFile("../assets/screens/ancool/fonts_pal.dat"));

// ONE plane (plane 0) carries all three layers, drawn in the old stacking
// order (stars, then letters, then scroller) after one CHISEL clear: each
// enabled plane costs ~0.59 Mc of FRESCO a frame on the board, and the three
// planes this screen used held a handful of pixels each. The palettes merge:
//   0          clear (the sprite and the composite key on its alpha 0)
//   1          the scroller's ink, rewritten per scanline (rasters.zig)
//   2 .. 36    the star gradient (stars.zig, plane 0's old entries 1..35)
//   LETTERS    the TCB letters' red (plane 1's old entry 1)
const LETTERS: u8 = 37;

const stars = @import("ancool/stars.zig");
const rasters = @import("ancool/rasters.zig");

const Vec3 = za.Vec3;
const Vec4 = za.Vec4;
const Mat4 = za.Mat4;
const wf = zg.wireframe;

// The T, C and B letters (25 vertices, 24 edges), placed in init().
const letters = zg.obj.parseWire(@embedFile("../assets/obj/ancool_tcb.obj"));
var vertices = wf.vec4s(letters.verts.len, letters.verts);

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------

pub const Demo = struct {
    frame_counter: u32 = 0,
    star_table: []u32 = &.{},
    scrolltext: Scrolltext(NB_FONTS) = undefined,
    cam: wf.Camera = undefined,
    projected_vertices: [letters.verts.len]Coord = undefined,
    angle_y: f32 = 0.0,
    angle_x: f32 = 0.0,
    angle_z: f32 = 0.0,
    zoom: f32 = 0.0,
    blitter: zg.Blitter = .{},

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        // Nothing happens until the user turns sound on — the request just waits.
        zg.requestSong(MUSIC);
        self.blitter.init();

        const fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(rasters.INK, font_pal[1]);
        stars.setPalette(fb);
        fb.setPaletteEntry(LETTERS, Color{ .r = 255, .g = 0, .b = 0, .a = 255 });
        fb.setFrameBufferHBLHandler(0, rasters.handler);

        self.star_table = zg.mem.mustAlloc(u32, stars.LEN * stars.NB);
        stars.build(self.star_table);
        self.initLetters();
        self.scrolltext = Scrolltext(NB_FONTS).init(fb.getRenderTarget(), fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 100, null, &g_y_offset_table_b, true);
    }

    fn initLetters(self: *Demo) void {
        self.cam = .{
            .projection = za.perspective(60.0, 200.0 / 320.0, 0.1, 100.0),
            .camera = za.camera(Vec3.new(0.0, 0.0, -10.0), 0, 0),
            .screen = za.screen(320, 200),
        };
        self.zoom = 0.8;
        for (&vertices) |*v| v.* = v.add(Vec4.new(0, 1.00, 2.8, 0));
        for (vertices[9..17]) |*v| v.* = v.add(Vec4.new(-0.5, 0, -0.5, 0)); // C
        for (vertices[17..25]) |*v| v.* = v.add(Vec4.new(-1.0, 0, -1.0, 0)); // B
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        self.frame_counter += 1;
        self.scrolltext.update();

        // The letters' own transform: scale, then one Euler X/Y/Z matrix, both
        // built once a frame (wf.Rot), not per vertex. Still f32: the angles
        // grow without bound, so the letters are not periodic bit for bit and a
        // table would drift from the original after a while (~0.02 Mc a frame).
        const zoom_spin = wf.Rot.chain(&.{
            Mat4.fromScale(Vec3.new(self.zoom, self.zoom, self.zoom)),
            Mat4.fromEulerAngles(Vec3.new(self.angle_x, self.angle_y, self.angle_z)),
        });
        self.cam.project(&vertices, &self.projected_vertices, zoom_spin, wf.Rot.apply);
        self.angle_x += 3;
        self.angle_y += 3.5;
        self.angle_z += 2;
        rasters.step();
        _ = zigos;
        _ = elapsed_time;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        // One CHISEL clear (1 px a clock), then the layers in stacking order.
        const fb = &zigos.lfbs[0];
        self.blitter.clear(fb, 0);
        stars.draw(fb.fb, self.star_table, self.frame_counter);
        wf.drawEdges(fb.getRenderTarget(), &letters.edges, &self.projected_vertices, LETTERS, shapes.drawLine);
        self.scrolltext.render();
        _ = elapsed_time;
    }
};
