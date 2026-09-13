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

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // Nothing happens until the user turns sound on — the request just waits.
        zg.requestSongTune(MUSIC, MUSIC_TUNE);

        // first plane
        var fb: *LogicalFB = &zigos.lfbs[0];

        fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        self.starfield = Starfield(NB_STARS).init(fb.getRenderTarget(), WIDTH, HEIGHT-64, 32, 1, 4, StarfieldDirection.LEFT);

        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(4, Color{ .r = 0xF0, .g = 0xF0, .b = 0xF0, .a = 255 });
        fb.setPaletteEntry(3, Color{ .r = 0xA0, .g = 0xA0, .b = 0xA0, .a = 255 });
        fb.setPaletteEntry(2, Color{ .r = 0x60, .g = 0x60, .b = 0x60, .a = 255 });
        fb.setPaletteEntry(1, Color{ .r = 0x40, .g = 0x40, .b = 0x40, .a = 255 });

        // 2nd plane
        fb = &zigos.lfbs[1];
        fb.is_enabled = true;
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(1, Color{ .r = 255, .g = 255, .b = 255, .a = 255 });
        self.cam = .{
            .projection = za.perspective(40.0, 200.0 / 320.0, 20, 1800),
            .camera = za.camera(Vec3.new(0.0, 0.0, -14.0), 0, 0),
            .screen = za.screen(320, 200),
        };

        for (&vertices) |*v| v.* = v.add(Vec4.new(-3.0, 0.50, 0.0, 0));

        // 3rd plane
        fb = &zigos.lfbs[2];
        fb.is_enabled = true;
        fb.setPalette(font_pal);

        self.scrolltext = Scrolltext(NB_FONTS).init(fb.getRenderTarget(), fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 0, null, null, null);

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.starfield.update();
        self.scrolltext.update();

        self.cam.project(&vertices, &self.projected_vertices, self, rotateXY);

        self.angle_x += 3.50;
        self.angle_y += 3.50;   

        _ = zigos;
        _ = elapsed_time;
    }

    // The logo's own transform: rotate about X, then Y (no Z, unlike maxi).
    fn rotateXY(self: *Demo, v: Vec4) Vec4 {
        const after_x = Mat4.fromEulerAngles(Vec3.new(self.angle_x, 0, 0)).vec4mulByMat4(v);
        return Mat4.fromEulerAngles(Vec3.new(0, self.angle_y, 0)).vec4mulByMat4(after_x);
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.starfield.target.clearFrameBuffer(0);
        self.starfield.render();

        var fb = &zigos.lfbs[1];
        fb.clearFrameBuffer(0);
        wf.drawEdges(fb.getRenderTarget(), &logo.edges, &self.projected_vertices, 1, shapes.drawLine);

        fb = &zigos.lfbs[2];
        fb.clearFrameBuffer(0);
        self.scrolltext.render();

        // copy scrolltext at the bottom
        var i: u16 = 0;
        while(i < WIDTH*SCROLL_CHAR_HEIGHT) : ( i += 1){
            fb.fb[i + ((HEIGHT-SCROLL_CHAR_HEIGHT) * WIDTH)] = fb.fb[i];
        }

        _ = elapsed_time;

    }
};
