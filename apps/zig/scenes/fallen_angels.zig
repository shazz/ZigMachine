// FALLEN ANGELS (The Empire / Golden Axe intro): a raster scroller, the logo
// and a rippling 3D grid, all on plane 0 (fallen_angels/layer.zig).
const std = @import("std");
const zg = @import("zigos");
const convertU8ArraytoColors = zg.convertU8ArraytoColors;

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const RenderBuffer = zg.RenderBuffer;
const Color = zg.Color;

const Scrolltext = zg.Scrolltext;

const za = zg.za;
const shapes = zg.shapes;
const Coord = shapes.Coord;

const Console = zg.Console;
const Rows = @import("rowblit.zig").Rows;
const layer = @import("fallen_angels/layer.zig");

const HEIGHT: u16 = zg.HEIGHT;
const WIDTH: u16 = zg.WIDTH;

// music — the screen's own tune, played by its own 68000 (docs/music/).
// "Count Zero 2" from the Ultimatum demo (ripped by Mug UK).
const MUSIC = "count_zero_2.sndh";

const fonts_b = @embedFile("../assets/screens/fallen_angels/fonts.raw");
const SCROLL_TEXT = "                                                                                                               THE EMPIRE PRESENTS : GOLDEN AXE,CRACKED,FILES,PACKED AND TRAINED BY ILLEGAL FROM THE FALLEN ANGELS ... DIS GREAT INTRO WAS CODED FOR ME BY -PROTEUS- HEHE !. THE EMPIRE IS COMPOSED OF  THE FALLEN ANGELS,THE MARVELLOUS V8,NOKTURNAL (HI RICK) AND MY GREETINGS ARE SENT TO : INNERCIRCLE ( GREAT MUZAK ! ),THE UNION,AUTOMATION ( GREAT PACKS ! ),HOTLINE ( LOTUS KEEP IT ON ! ),EQUINOX,MCODER,ST CONNEXION,RFA ALLIANCE,PHALANX,ZAE. ENJOY THIS GAME.FRENCH MESSAGE TO STEPRATE : OREILIEN FILS DE RIEN,PETIT FILS DE RIEN ETC....                                                       ?!?                                  AS YOU WANNA STAY,HERE IS A GAME FOR YOU , DECODE IT : 4954204953204F4256494F55532054484154204C414D4552532048494444454E20494E2054484520464F4C4C4F57494E4720574F524453204F4620544845205343524F4C4C5445585420284F4E4C5920534F4D45204D454D42455253204C494B45204652454444592C4D415A4F555420414E4420434F2E2E2E29  ( I THINK I DID NOT MISS THE CODES ),HEY REPLICANTS,ARE YOU SLEEPING ?.                                                          ";
const SCROLL_CHAR_WIDTH = 8; 
const SCROLL_CHAR_HEIGHT = 7;
const SCROLL_SPEED = 3;
const SCROLL_CHARS = " ! #$%&'()*+,-./0123456789:;<=>? ABCDEFGHIJKLMNOPQRSTUVWXYZ";
pub const NB_FONTS: u8 = WIDTH*2 / SCROLL_CHAR_WIDTH + 1;

// palettes (the logo's and the grid's colours: fallen_angels/layer.zig)
const fonts_pal = convertU8ArraytoColors(@embedFile("../assets/screens/fallen_angels/fonts_pal.dat"));

const rasters_b = convertU8ArraytoColors(@embedFile("../assets/screens/fallen_angels/rasters.dat"));

const Vec3 = za.Vec3;
const Vec4 = za.Vec4;
const wf = zg.wireframe;

// The 6x6 rippling grid (36 vertices, 25 quads = 100 edges). The file holds
// the flat base; update() rewrites every z with the ripple before projecting.
const grid = zg.obj.parseWire(@embedFile("../assets/obj/fallen_angels_grid.obj"));
var grid_vertices = wf.vec4s(grid.verts.len, grid.verts);
const grid_edges = layer.uniqueEdges(&grid.edges);


// Rasters: the scroller ink (plane 0, entry 1) takes rasters_b[line] on visible
// line `line`. Played by zg.copper, whose tables are PHYSICAL rows: a per-plane
// handler on this normal plane receives LOGICAL lines 0..199, and the old
// hand-written handler tested physical 40..239, so the top 40 lines kept a
// stale colour and the last five bands never showed.
const copper = zg.copper;
const SCROLL_INK = layer.SCROLL_INK;
var raster_tables: [1]copper.Table = undefined;

// The scroller's 640x7 strip. Module scope: init() used to point the scroller at
// a buffer on its own stack, which every later call overwrote.
var scroll_pixels = [_]u8{0} ** (WIDTH * 2 * SCROLL_CHAR_HEIGHT);
var scroll_buffer: RenderBuffer = .{ .buffer = &scroll_pixels, .width = WIDTH * 2, .height = SCROLL_CHAR_HEIGHT };

pub const Demo = struct {
  
    name: u8 = 0,
    scrolltext: Scrolltext(NB_FONTS) = undefined,
    logo_x: i32 = WIDTH / 2 - 45,
    scroller_target: zg.RenderTarget = undefined,
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
    blitter: zg.Blitter = .{},

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // Nothing happens until the user turns sound on — the request just waits.
        zg.requestSong(MUSIC);

        self.blitter.init();

        // first plane
        const fb: *LogicalFB = &zigos.lfbs[0]; // the only plane
        fb.is_enabled = true;
        self.blitter.clear(fb, 0); // the scroller's gap rows are never drawn again
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

        // The logo and the grid draw on this plane too, over the scroller
        // (fallen_angels/layer.zig): planes 1 and 2 stay disabled.
        layer.setPalette(fb);
        self.sin_counter = 0;

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
        self.logo_x = 160 - 45 + @as(i16, @intFromFloat(x_pos));

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

        // The spin's matrices once a frame, not per vertex (wf.Rot).
        const spin = wf.Rot.xyz(self.angle_x, self.angle_y, self.angle_z);
        self.cam.project(&grid_vertices, &self.grid_projected_vertices, spin, wf.Rot.apply);

        // not sure when time_Counter becomes nan ???
        // self.time_counter += elapsed_time;
        self.time_counter += 16;

        _ = elapsed_time;
        _ = zigos;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        // One plane, back to front (fallen_angels/layer.zig): the gap rows
        // cleared, the scroller as 25 CHISEL blits (a line of 7 rows each,
        // straight off the 640-wide strip), the logo keyed, the grid.
        const fb: *LogicalFB = &zigos.lfbs[0];
        layer.clearGapRows(fb);

        self.scroller_target.clearFrameBuffer(0);
        self.scrolltext.render();

        const strip = @intFromPtr(self.scroller_target.render_buffer.buffer.ptr);
        var rows = Rows.open(fb, WIDTH * 2, null);
        var i: u16 = 0;
        while(i < 25) : ( i += 1) {
            // The line's x offset: a sine once the intro is over, else a
            // slant. One sin per LINE (it was recomputed for each of its 7 rows,
            // a libm sinf in soft f64 every time).
            const offset_x: u16 = if (self.time_counter > 7*16*50)
                @as(u16, @intFromFloat(self.scroll_sinx_incr + (@sin(self.scroll_sinx + (@as(f32, @floatFromInt(i))/5.0)) * self.scroll_sinx_incr)))
            else
                i*3;
            rows.blit(strip + offset_x, 0, @intCast(i * 8), WIDTH, SCROLL_CHAR_HEIGHT);
        }

        layer.drawLogo(fb, self.logo_x, HEIGHT - layer.LOGO_H);
        if (self.time_counter > 16*60*6) layer.drawGrid(fb, grid_edges, &self.grid_projected_vertices);

        _ = elapsed_time;
    }
};
