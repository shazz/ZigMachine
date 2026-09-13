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
const RenderTarget = zg.RenderTarget;
const RenderBuffer = zg.RenderBuffer;
const Color = zg.Color;

const Scrolltext = zg.Scrolltext;
const Sprite = zg.Sprite;
const Background = zg.Background;

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
// "Count Zero 2" from the Ultimatum demo (ripped by Mug UK).
const MUSIC = "count_zero_2.sndh";

// scrolltext

const fonts_b = @embedFile("../assets/screens/fallen_angels/fonts.raw");
const SCROLL_TEXT = "                                                                                                               THE EMPIRE PRESENTS : GOLDEN AXE,CRACKED,FILES,PACKED AND TRAINED BY ILLEGAL FROM THE FALLEN ANGELS ... DIS GREAT INTRO WAS CODED FOR ME BY -PROTEUS- HEHE !. THE EMPIRE IS COMPOSED OF  THE FALLEN ANGELS,THE MARVELLOUS V8,NOKTURNAL (HI RICK) AND MY GREETINGS ARE SENT TO : INNERCIRCLE ( GREAT MUZAK ! ),THE UNION,AUTOMATION ( GREAT PACKS ! ),HOTLINE ( LOTUS KEEP IT ON ! ),EQUINOX,MCODER,ST CONNEXION,RFA ALLIANCE,PHALANX,ZAE. ENJOY THIS GAME.FRENCH MESSAGE TO STEPRATE : OREILIEN FILS DE RIEN,PETIT FILS DE RIEN ETC....                                                       ?!?                                  AS YOU WANNA STAY,HERE IS A GAME FOR YOU , DECODE IT : 4954204953204F4256494F55532054484154204C414D4552532048494444454E20494E2054484520464F4C4C4F57494E4720574F524453204F4620544845205343524F4C4C5445585420284F4E4C5920534F4D45204D454D42455253204C494B45204652454444592C4D415A4F555420414E4420434F2E2E2E29  ( I THINK I DID NOT MISS THE CODES ),HEY REPLICANTS,ARE YOU SLEEPING ?.                                                          ";
const SCROLL_CHAR_WIDTH = 8; 
const SCROLL_CHAR_HEIGHT = 7;
const SCROLL_SPEED = 3;
const SCROLL_CHARS = " ! #$%&'()*+,-./0123456789:;<=>? ABCDEFGHIJKLMNOPQRSTUVWXYZ";
pub const NB_FONTS: u8 = WIDTH*2 / SCROLL_CHAR_WIDTH + 1;

// palettes
const logo_pal = convertU8ArraytoColors(@embedFile("../assets/screens/fallen_angels/logo_pal.dat"));
const fonts_pal = convertU8ArraytoColors(@embedFile("../assets/screens/fallen_angels/fonts_pal.dat"));

// rasters
const rasters_b = convertU8ArraytoColors(@embedFile("../assets/screens/fallen_angels/rasters.dat"));

// logo
const logo_b = @embedFile("../assets/screens/fallen_angels/logo.raw");

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------

const Vec3 = za.Vec3;
const Vec4 = za.Vec4;
const wf = zg.wireframe;

// The 6x6 rippling grid (36 vertices, 25 quads = 100 edges). The file holds
// the flat base; update() rewrites every z with the ripple before projecting.
const grid = zg.obj.parseWire(@embedFile("../assets/obj/fallen_angels_grid.obj"));
var grid_vertices = wf.vec4s(grid.verts.len, grid.verts);


// Rasters: the scroller ink (plane 0, entry 1) takes rasters_b[line] on visible
// line `line`. Played by zg.copper, whose tables are PHYSICAL rows: a per-plane
// handler on this normal plane receives LOGICAL lines 0..199, and the old
// hand-written handler tested physical 40..239, so the top 40 lines kept a
// stale colour and the last five bands never showed.
const copper = zg.copper;
const SCROLL_INK: u8 = 1;
var raster_tables: [1]copper.Table = undefined;

// The scroller's 640x7 strip. Module scope: init() used to point the scroller at
// a buffer on its own stack, which every later call overwrote.
var scroll_pixels = [_]u8{0} ** (WIDTH * 2 * SCROLL_CHAR_HEIGHT);
var scroll_buffer: RenderBuffer = .{ .buffer = &scroll_pixels, .width = WIDTH * 2, .height = SCROLL_CHAR_HEIGHT };

pub const Demo = struct {
  
    name: u8 = 0,
    scrolltext: Scrolltext(NB_FONTS) = undefined,
    logo: Sprite = undefined,
    scroller_target: RenderTarget = undefined,
    sin_counter: f32 = undefined,
    logo_sinx: f32 = 0,
    scroll_sinx: f32 = 0,
    scroll_sinx_incr: f32 = 0,
    cam: wf.Camera = undefined,
    grid_projected_vertices: [grid.verts.len]Coord = undefined,
    angle_y: f32 = 0.0,
    angle_x: f32 = 0.0,
    angle_z: f32 = 0.0,    
    time_counter: f32 = 0.0,
    distort: f32 = 0.0,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // Nothing happens until the user turns sound on — the request just waits.
        zg.requestSong(MUSIC);

        // first plane
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPalette(fonts_pal);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        
        // raster effect: the ink is transparent outside the visible band, as before
        copper.install(fb, &.{SCROLL_INK}, &raster_tables, .{});
        @memset(copper.table(fb, 0), (Color{ .r = 0, .g = 0, .b = 0, .a = 0 }).toRGBA());
        for (copper.visible(fb, 0), rasters_b[0..HEIGHT]) |*row, c| row.* = c.toRGBA();

        self.scroller_target = .{ .render_buffer = &scroll_buffer };
        self.scrolltext = Scrolltext(NB_FONTS).init(self.scroller_target, fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 0, null, null, false);

        self.scroll_sinx = 20;
        self.scroll_sinx_incr = 20;

        // second plane
        fb = &zigos.lfbs[1];
        fb.is_enabled = true; 

        fb.setPalette(logo_pal);
        fb.setPaletteEntry(1, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });      

        self.logo.init(fb.getRenderTarget(), logo_b, 89, 16, WIDTH/2-45, HEIGHT-16, null, null); 
        self.sin_counter = 0;

        // third plane
        fb = &zigos.lfbs[2];
        fb.is_enabled = true; 
        // set lines colors
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(1, Color{ .r = 0xff, .g = 0x00, .b = 0x00, .a = 255 });

        self.cam = .{
            .projection = za.perspective(40.0, 200.0 / 320.0, 1, 1000),
            .camera = za.camera(Vec3.new(0.0, 0.0, -1.4), 0, 0),
            .screen = za.screen(320, 200),
        };

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.logo_sinx += 0.05;

        const x_pos: f32 = @sin(self.logo_sinx) * 116;
        self.logo.update(160 - 45 + @as(i16, @intFromFloat(x_pos)), HEIGHT-16, null, null);

        if(self.time_counter > 7*16*50) {
            self.scroll_sinx += 0.1;
            self.scroll_sinx_incr += 0.02;
            if(self.scroll_sinx_incr >= 50) self.scroll_sinx_incr = 2.0;
        }
        
        self.scrolltext.update();

        const base_incr = 0.55;
        self.angle_x -= (base_incr * 1);
        self.angle_y -= (base_incr * 2);
        self.angle_z -= (base_incr * 4);

        // add wave to vertices
        self.distort += 0.08;

        var i: usize = 0;
        while(i < grid_vertices.len) : (i += 1) {
            const long: f32 = std.math.sqrt((grid_vertices[i].x() * grid_vertices[i].x()) + (grid_vertices[i].y() * grid_vertices[i].y()));
            const offset: f32 = 0.15 * @sin(self.distort - long * ((2.0 * std.math.pi) / 0.9));

            grid_vertices[i] = Vec4.new(grid_vertices[i].x(), grid_vertices[i].y(), offset, 1.0);
        }        

        self.cam.project(&grid_vertices, &self.grid_projected_vertices, self, spin);

        // not sure when time_Counter becomes nan ???
        // self.time_counter += elapsed_time;
        self.time_counter += 16;

        _ = elapsed_time;
        _ = zigos;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        // copy render target to fb
        var fb: *LogicalFB = &zigos.lfbs[0];

        self.scroller_target.clearFrameBuffer(0);
        self.scrolltext.render();

        var i: u16 = 0;
        while(i < 25) : ( i += 1) {
            // rows 0..6 come from the 7-row strip; row 7 is the gap between lines
            // (reading it went past the strip, into whatever lay after it)
            @memset(fb.fb[(i * 8 + SCROLL_CHAR_HEIGHT) * WIDTH ..][0..WIDTH], 0);
            var y: u16 = 0;
            while(y < SCROLL_CHAR_HEIGHT) : (y += 1){
                var x: u16 = 0;

                // no sin at the beginning just decrement
                if(self.time_counter > 7*16*50) {
                    const f_sin: f32 = self.scroll_sinx_incr + (@sin(self.scroll_sinx + (@as(f32, @floatFromInt(i))/5.0)) * self.scroll_sinx_incr);
                    const offset_x: u16 = @as(u16, @intFromFloat(f_sin));

                    while(x < WIDTH) : (x += 1) {
                        fb.fb[x + y*WIDTH + (i*8*WIDTH)] = self.scroller_target.render_buffer.buffer[offset_x + x + y*WIDTH*2];
                    }
                } else {
                    const offset_x: u16 = i*3;
                    while(x < WIDTH) : (x += 1) {
                        fb.fb[x + y*WIDTH + (i*8*WIDTH)] = self.scroller_target.render_buffer.buffer[offset_x + x + y*WIDTH*2];
                    }
                }
            }
        }

        fb = &zigos.lfbs[1];
        fb.clearFrameBuffer(1);
        self.logo.render(null);        

        if(self.time_counter > 16*60*6) {
            fb = &zigos.lfbs[2];
            fb.clearFrameBuffer(0);
            wf.drawEdges(fb.getRenderTarget(), &grid.edges, &self.grid_projected_vertices, 1, shapes.drawLine);
        }

        _ = elapsed_time;
    }

    fn spin(self: *Demo, v: Vec4) Vec4 {
        return wf.rotateXYZ(v, self.angle_x, self.angle_y, self.angle_z);
    }
};
