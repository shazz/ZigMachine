// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const readU16Array = zg.readU16Array;
const readI16Array = zg.readI16Array;
const convertU8ArraytoColors = zg.convertU8ArraytoColors;

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;

const Starfield = zg.Starfield;
const StarfieldDirection = zg.StarfieldDirection;

const Scrolltext = zg.Scrolltext;
const za = zg.za;
const shapes = zg.shapes;
const Coord = shapes.Coord;

const Console = zg.Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = zg.HEIGHT;
const WIDTH: u16 = zg.WIDTH;

// music — the screen's own tune, played by its own 68000 (docs/music/).
// Mad Max (Jochen Hippel), "Leavin Teramis" (1990) — the screen's own
// scrolltext credits him. The image holds 11 subtunes; this screen wants
// the 9th, so it must ask by number as well as by name.
const MUSIC = "leavin_teramis.sndh";
const MUSIC_TUNE: u8 = 9;

// scrolltext
pub const NB_FONTS: u8 = 11;
const fonts_b = @embedFile("../assets/screens/empire/fonts2_pal.raw");
const SCROLL_TEXT = "             THE EMPIRE PRESENTS A NEW LITTLE INTRO FROM THE FALLEN ANGELS. CODE BY STEF, FONTS BY STARFIX, AND MUSEXX BY JOCHEN HIPPEL. THE GREETINGS GO TO: ST-CONNEXION, TECHNOCRATS AND....   AND....   ZE WATSIT.      OK, THAT'S ALL FOLKS!      BYE FREAKS.....";
const SCROLL_CHAR_WIDTH = 32; 
const SCROLL_CHAR_HEIGHT = 32;
const SCROLL_SPEED = 4;
const SCROLL_CHARS = " ! #$%&'()*+,-./0123456789:;<=>? ABCDEFGHIJKLMNOPQRSTUVWXYZ";

// palettes
const font_pal = convertU8ArraytoColors(@embedFile("../assets/screens/empire/fonts2_pal.dat"));

// Stars
const NB_STARS = 150;

const Vec3 = za.Vec3;
const Vec4 = za.Vec4;
const Mat4 = za.Mat4;
const wf = zg.wireframe;

// The EMPIRE logo (35 vertices, 27 edges), centred in init().
const logo = zg.obj.parseWire(@embedFile("../assets/obj/empire_logo.obj"));
var vertices = wf.vec4s(logo.verts.len, logo.verts);

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------
// One plane for the three layers: the font is 0..12, the stars' greys and the
// logo's white go above it.
const STAR_BASE: u8 = 12; // + the star's speed 1..4
const LOGO_INK: u8 = 17;

// The scroller's letters go straight onto the plane, twice (top and bottom
// band), as CHISEL cookie-cut blits from the font: index 0 is see-through, as
// it was on the scroller's own plane. ZIGGY used to draw them a pixel at a time
// into a 320x32 band and lay the band over the plane, about 0.8 Mc a frame of
// byte stores; each letter is now one blit (11 a band). Same clamping as
// Sprite.render() into a 320-wide band at y 0, so the same pixels.
fn blitScroller(bl: *zg.Blitter, fb: *LogicalFB, st: anytype, y: i16) void {
    for (&st.fonts) |*font| {
        const x = font.sprite.x_position;
        if (x >= WIDTH or x + SCROLL_CHAR_WIDTH < 0) continue;
        const skip: u16 = if (x < 0) @intCast(-x) else 0;
        const left: u16 = if (x < 0) 0 else @intCast(x);
        const cols: u16 = @min(SCROLL_CHAR_WIDTH - skip, WIDTH - left);
        if (cols == 0) continue;
        bl.blitImage(fb, @intCast(left), y, font.sprite.data, SCROLL_CHAR_WIDTH, skip, 0, cols, SCROLL_CHAR_HEIGHT, 0);
    }
}

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------

pub const Demo = struct {
  
    name: u8 = 0,
    frame_counter: u32 = 0,
    starfield: Starfield(NB_STARS) = undefined,
    scrolltext: Scrolltext(NB_FONTS) = undefined,
    cam: wf.Camera = undefined,
    projected_vertices: [logo.verts.len]Coord = undefined,
    angle_y: f32 = 0.0,
    angle_x: f32 = 0.0,
    blitter: zg.Blitter = .{},

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // Nothing happens until the user turns sound on — the request just waits.
        zg.requestSongTune(MUSIC, MUSIC_TUNE);

        // ONE plane. The screen used three (stars, logo, scroller), and every
        // enabled plane is a full compositor pass a frame (about 0.8 Mc on the
        // board); they never needed to be apart. The font keeps its own indices
        // (0..12), the stars and the logo take free entries above them, and the
        // layers are drawn bottom to top, so the picture is the one the three
        // planes composed.
        const fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        self.blitter.init();
        fb.setPalette(font_pal);
        fb.setPaletteEntry(STAR_BASE + 4, Color{ .r = 0xF0, .g = 0xF0, .b = 0xF0, .a = 255 });
        fb.setPaletteEntry(STAR_BASE + 3, Color{ .r = 0xA0, .g = 0xA0, .b = 0xA0, .a = 255 });
        fb.setPaletteEntry(STAR_BASE + 2, Color{ .r = 0x60, .g = 0x60, .b = 0x60, .a = 255 });
        fb.setPaletteEntry(STAR_BASE + 1, Color{ .r = 0x40, .g = 0x40, .b = 0x40, .a = 255 });
        fb.setPaletteEntry(LOGO_INK, Color{ .r = 255, .g = 255, .b = 255, .a = 255 });

        self.starfield = Starfield(NB_STARS).init(fb.getRenderTarget(), WIDTH, HEIGHT-64, 32, 1, 4, StarfieldDirection.LEFT);
        for (&self.starfield.starfield_table) |*star| star.color += STAR_BASE; // speed 1..4 -> its grey

        self.cam = .{
            .projection = za.perspective(40.0, 200.0 / 320.0, 20, 1800),
            .camera = za.camera(Vec3.new(0.0, 0.0, -14.0), 0, 0),
            .screen = za.screen(320, 200),
        };

        for (&vertices) |*v| v.* = v.add(Vec4.new(-3.0, 0.50, 0.0, 0));

        // the scroller only keeps the letters' positions: render() blits them
        self.scrolltext = Scrolltext(NB_FONTS).init(fb.getRenderTarget(), fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 0, null, null, null);

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.starfield.update();
        self.scrolltext.update();

        // The logo's own transform: rotate about X, then Y (no Z, unlike maxi),
        // the matrices built once for the frame's 35 vertices.
        const spin = wf.Rot.chain(&.{
            Mat4.fromEulerAngles(Vec3.new(self.angle_x, 0, 0)),
            Mat4.fromEulerAngles(Vec3.new(0, self.angle_y, 0)),
        });
        self.cam.project(&vertices, &self.projected_vertices, spin, wf.Rot.apply);

        self.angle_x += 3.50;
        self.angle_y += 3.50;   

        _ = zigos;
        _ = elapsed_time;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        const fb = &zigos.lfbs[0];
        self.blitter.clear(fb, 0); // CHISEL fills the plane; ZIGGY stored 64,000 bytes
        self.starfield.render();
        wf.drawEdges(fb.getRenderTarget(), &logo.edges, &self.projected_vertices, LOGO_INK, shapes.drawLine);

        // the scroller on top, at the top and again at the bottom
        blitScroller(&self.blitter, fb, &self.scrolltext, 0);
        blitScroller(&self.blitter, fb, &self.scrolltext, HEIGHT - SCROLL_CHAR_HEIGHT);

        _ = elapsed_time;
    }
};
