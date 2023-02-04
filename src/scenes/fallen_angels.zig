// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const readU16Array = @import("../utils/loaders.zig").readU16Array;
const readI16Array = @import("../utils/loaders.zig").readI16Array;
const convertU8ArraytoColors = @import("../utils/loaders.zig").convertU8ArraytoColors;

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const RenderTarget = @import("../zigos.zig").RenderTarget;
const RenderBuffer = @import("../zigos.zig").RenderBuffer;
const Color = @import("../zigos.zig").Color;

const Scrolltext = @import("../effects/scrolltext.zig").Scrolltext;
const Sprite = @import("../effects/sprite.zig").Sprite;
const Background = @import("../effects/background.zig").Background;

const za = @import("../utils/zalgebra.zig");
const shapes = @import("../effects/shapes.zig");
const Coord = shapes.Coord;

const Console = @import("../utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = @import("../zigos.zig").HEIGHT;
const WIDTH: u16 = @import("../zigos.zig").WIDTH;

// scrolltext

const fonts_b = @embedFile("../assets/screens/fallen_angels/fonts.raw");
const SCROLL_TEXT = "                                                                                                                       "
    ++ "THE EMPIRE PRESENTS : MEAN STREET,CRACKED BY ILLEGAL FROM THE FALLEN ANGELS ... DIS GREAT INTRO WAS CODED FOR ME BY -PROTEUS- HEHE !"
	++ ". LIGHTMAN SAYS : THANX TO THE ST AMIGOS TO HAVE RELEASED A PROTECTED ORIGINAL,IT IS MAYBE BECAUSE THE REPLICANTS ARE NOT ABLE TO CRACK IT !"
	++ "  AS USUAL,BEFORE YOU GO FURTHER,HERE IS WHAT WE ARE : THE EMPIRE IS COMPOSED OF  THE FALLEN ANGELS,THE MARVELLOUS V8,NOKTURNAL AND MY "
	++ "GREETINGS ARE SENT TO : INNERCIRCLE ( GREAT MUZAK ! ),THE UNION,AUTOMATION ( GREAT PACKS ! ),HOTLINE ( LOTUS KEEP IT ON ! ),EQUINOX,MCODER,"
	++ "ST CONNEXION,RFA ALLIANCE,PHALANX,ZAE,THE MASTERS ( HI MASTER GIN !,YOU ARE ATTRACTIVE ! ). ONE DAY,I HAD ZAE AT THE PHONE,ZAE ! I WANNA MAKE"
	++ " MY OWN CHARTS AND HERE THEY ARE : BEST DEMOS : 1-CUDDLY DEMOS ( IT IS THE BEST IN ITS CONTEXT ),2-MIND BOMB,3-DELIRIOUS II,4-INNERCIRCLE,5-UNION"
	++ " DEMO ( THE FIRST WHICH WAS ABLE TO ENTER A TOP FIVE ).BEST GRAPHIXX ( FOR THE GUYS I KNOW THE GRAPHIXX ) : 1-ES ( BEST SPRITES WITH A FEW COLORS"
	++ " ),2-KRAZY REX I DO NOT KNOW FOR THE OTHERS...,BEST PACKERS : 1-AUTOMATION,2-MEDWAY BOYZ,3-POMPEY PIRATES,4-RIPPED OFF ,BEST MUZAK MAKERS 1-MAD MAX"
	++ " ( OF COURSE ! ),2-JOARD ( YES,I THINK YOUR MUSIXX ARE GREAT ),3- COUNT ZERO ( GREAT PLAYER ),4-CRISPY NOODLE,5-CHRIS MAD BEST GAME DESIGNERS :"
	++ " 1-THALION SOFTWARE,2-PSYGNOSYS,3-HEWSON ( I LIKE ELIMINATOR OR NEBULUS,THE JMP GAMES. ),4-RAINBOW ARTS,5-OCEAN ( I THINK I FORGOT NONE BEFORE"
	++ " OCEAN BUT I WILL THINK ABOUT IT AGAIN ... ).... AND I WILL NOT GIVE YA A CRACKERS CLASSEMENT BECAUSE AS I AM A CRACKER,I CANNOT GIVE MY"
	++ " OPINION..THAT WAS ALL FOR ZAE.NOW HERE ARE THE MESSAGES : FIRST,HI TO WEREWOLF WHO HAS ENTERED TM V8.OK AND I UNDERSTAND IT,WEREWOLF ( I WOULD"
	++ " HAVE DONE IT TOO AT YOUR POSITION,GUILLAUME ! ).HI TO ZARATHUSTRA ( REMEMBER THE NIGHT WHEN YOU WERE TRYING TO MAKE ( YOUR ) KEYBOARD WORK ( ... )"
	++ " ) AND ALTAIR. HI TO KRUEGER AND STEPRATE ( EVEN WITH YOUR JACKET,YOU ARE THE SAME ),CHECKSUM ( WILL TRY TO INSTALL MY LOADERS ON SIDE 2 ! )."
	++ " CONSTELLATIONS ( ELYSEE TU ABUSES... ),BLACK CATS ( FIND YOU ATTRACTIVE ! ) ST CONNEXION ( TRY TO DECODE IT : CHELONCH MARLONCH MAGNE TECH FECH"
	++ " ),PROTEUS ( LA NOUVELLE MARQUE DE BOULES DE BAINS ). OK NOW I AM TIRED AND I WANNA SLEEP SO SCHLUPZ !!!!!!!      ";
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
var raster_index: u8 = 0;

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------

const Vec2 = za.Vec2;
const Vec3 = za.Vec3;
const Vec4 = za.Vec4;
const Mat4 = za.Mat4;

var grid_vertices = [_]Vec4{
    Vec4.new(-0.30, 0.30, 0.0, 1.0),
    Vec4.new(-0.18, 0.30, 0.0, 1.0),
    Vec4.new(-0.06, 0.30, 0.0, 1.0),
    Vec4.new(0.06, 0.30, 0.0, 1.0),
    Vec4.new(0.18, 0.30, 0.0, 1.0),
    Vec4.new(0.30, 0.30, 0.0, 1.0),

    Vec4.new(-0.30, 0.18, 0, 1.0),
    Vec4.new(-0.18, 0.18, 0, 1.0),
    Vec4.new(-0.06, 0.18, 0, 1.0),
    Vec4.new(0.06, 0.18, 0, 1.0),
    Vec4.new(0.18, 0.18, 0, 1.0),
    Vec4.new(0.30, 0.18, 0, 1.0),

    Vec4.new(-0.30, 0.06, 0, 1.0),
    Vec4.new(-0.18, 0.06, 0, 1.0),
    Vec4.new(-0.06, 0.06, 0, 1.0),
    Vec4.new(0.06, 0.06, 0, 1.0),
    Vec4.new(0.18, 0.06, 0, 1.0),
    Vec4.new(0.30, 0.06, 0, 1.0),

    Vec4.new(-0.30, -0.06, 0, 1.0),
    Vec4.new(-0.18, -0.06, 0, 1.0),
    Vec4.new(-0.06, -0.06, 0, 1.0),
    Vec4.new(0.06, -0.06, 0, 1.0),
    Vec4.new(0.18, -0.06, 0, 1.0),
    Vec4.new(0.30, -0.06, 0, 1.0),

    Vec4.new(-0.30, -0.18, 0, 1.0),
    Vec4.new(-0.18, -0.18, 0, 1.0),
    Vec4.new(-0.06, -0.18, 0, 1.0),
    Vec4.new(0.06, -0.18, 0, 1.0),
    Vec4.new(0.18, -0.18, 0, 1.0),
    Vec4.new(0.30, -0.18, 0, 1.0),

    Vec4.new(-0.30, -0.30, 0, 1.0),
    Vec4.new(-0.18, -0.30, 0, 1.0),
    Vec4.new(-0.06, -0.30, 0, 1.0),
    Vec4.new(0.06, -0.30, 0, 1.0),
    Vec4.new(0.18, -0.30, 0, 1.0),
    Vec4.new(0.30, -0.30, 0, 1.0)
};

var grid_segments = [_]Vec4{
		Vec4.new(0, 1, 7, 6),
		Vec4.new(1, 2, 8, 7),
		Vec4.new(2, 3, 9, 8),
		Vec4.new(3, 4, 10, 9),
		Vec4.new(4, 5, 11, 10),

		Vec4.new(6, 7, 13, 12),
		Vec4.new(7, 8, 14, 13),
		Vec4.new(8, 9, 15, 14),
		Vec4.new(9, 10, 16, 15),
		Vec4.new(10, 11, 17, 16),

		Vec4.new(12, 13, 19, 18),
		Vec4.new(13, 14, 20, 19),
		Vec4.new(14, 15, 21, 20),
		Vec4.new(15, 16, 22, 21),
		Vec4.new(16, 17, 23, 22),

		Vec4.new(18, 19, 25, 24),
		Vec4.new(19, 20, 26, 25),
		Vec4.new(20, 21, 27, 26),
		Vec4.new(21, 22, 28, 27),
		Vec4.new(22, 23, 29, 28),

		Vec4.new(24, 25, 31, 30),
		Vec4.new(25, 26, 32, 31),
		Vec4.new(26, 27, 33, 32),
		Vec4.new(27, 28, 34, 33),
		Vec4.new(28, 29, 35, 34)
};


fn handler_scroller(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {
    const back_color: Color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    if (line >= 40 and line < 240 ) {
        fb.setPaletteEntry(1, rasters_b[(line - 40)]);
    }
    if (line == 240) {
        fb.setPaletteEntry(1, back_color);
    }
    _ = zigos;
    _ = col;
}

pub const Demo = struct {
  
    name: u8 = 0,
    scrolltext: Scrolltext(NB_FONTS) = undefined,
    logo: Sprite = undefined,
    scroller_target: RenderTarget = undefined,
    sin_counter: f32 = undefined,
    logo_sinx: f32 = 0,
    scroll_sinx: f32 = 0,
    scroll_sinx_incr: f32 = 50,
    projection: Mat4 = undefined,
    camera: Mat4 = undefined,
    screen: Mat4 = undefined,
    grid_projected_vertices: [36]Coord = undefined,
    angle_y: f32 = 0.0,
    angle_x: f32 = 0.0,
    angle_z: f32 = 0.0,    
    time_counter: f32 = 0.0,
    distort: f32 = 0.0,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // first plane
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPalette(fonts_pal);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        
        // HBL Handler for the raster effect
        fb.setFrameBufferHBLHandler(40, handler_scroller);        

        var buffer = [_]u8{0} ** (WIDTH * 2 * SCROLL_CHAR_HEIGHT); 
        var render_buffer: RenderBuffer = .{ .buffer = &buffer, .width = WIDTH * 2, .height = HEIGHT };  
        self.scroller_target = .{ .render_buffer = &render_buffer };   
        self.scrolltext = Scrolltext(NB_FONTS).init(self.scroller_target, fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 0, null, null, false);

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

        self.projection = za.perspective(40.0, 200.0 / 320.0, 1, 1000);
        self.camera = za.camera(Vec3.new(0.0, 0.0, -1.4), 0, 0);
        self.screen = za.screen(320, 200);   

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.logo_sinx += 0.05;

        const x_pos: f32 = @sin(self.logo_sinx) * 116;
        self.logo.update(160 - 45 + @floatToInt(i16, x_pos), HEIGHT-16, null, null);

        self.scroll_sinx += 0.1;
        self.scroll_sinx_incr -= 0.02;
        if(self.scroll_sinx_incr <= 2) self.scroll_sinx_incr = 50.0;

        self.scrolltext.update();

        const base_incr = 0.55;
        self.angle_x -= (base_incr * 1);
        self.angle_y -= (base_incr * 2);
        self.angle_z -= (base_incr * 4);

        // add wave to vertices
        self.distort += 0.08;

        var i: usize = 0;
        while(i < grid_vertices.len) : (i += 1) {
			var long: f32 = std.math.sqrt((grid_vertices[i].x() * grid_vertices[i].x()) + (grid_vertices[i].y() * grid_vertices[i].y()));
            var offset: f32 = 0.15 * @sin(self.distort - long * ((2.0 * std.math.pi) / 0.9));

            grid_vertices[i] = Vec4.new(grid_vertices[i].x(), grid_vertices[i].y(), offset, 1.0);
		}        

        self.transform_object(self.angle_x, self.angle_y, self.angle_z, &grid_vertices, &self.grid_projected_vertices);        

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
            var y: u16 = 0;
            while(y < 8) : (y += 1){
                var x: u16 = 0;
                const f_sin: f32 = self.scroll_sinx_incr + (@sin(self.scroll_sinx + (@intToFloat(f32, i)/5.0)) * self.scroll_sinx_incr);
                const offset_x: u16 = @floatToInt(u16, f_sin);

                while(x < WIDTH) : (x += 1) {
                    fb.fb[x + y*WIDTH + (i*8*WIDTH)] = self.scroller_target.render_buffer.buffer[offset_x + x + y*WIDTH*2];
                }
            }
        }

        fb = &zigos.lfbs[1];
        fb.clearFrameBuffer(1);
        self.logo.render();        

        if(self.time_counter > 0) { //16*60*6) {
            fb = &zigos.lfbs[2];
            fb.clearFrameBuffer(0);
            self.render_object(fb.getRenderTarget(), &grid_segments, &self.grid_projected_vertices, 1);
        }

        _ = elapsed_time;
    } 

 fn transform_object(self: *Demo, angle_x: f32, angle_y: f32, angle_z: f32, vertices: []Vec4, projected_vertices: []Coord) void {

        for(vertices) |vertex, idx| {

            const rot_matx = Mat4.fromEulerAngles(Vec3.new(angle_x, 0, 0));
            const vertex_after_rotx = rot_matx.vec4mulByMat4(vertex);

            const rot_maty = Mat4.fromEulerAngles(Vec3.new(0, angle_y, 0));
            const vertex_after_roty = rot_maty.vec4mulByMat4(vertex_after_rotx);

            const rot_matz = Mat4.fromEulerAngles(Vec3.new(0, 0, angle_z));
            const vertex_after_rotz = rot_matz.vec4mulByMat4(vertex_after_roty); 
      
            const vertex_after_cam = self.camera.vec4mulByMat4(vertex_after_rotz);
            const vertex_after_proj = self.projection.vec4mulByMat4(vertex_after_cam);
                    
            const norm = Vec4.set(1/vertex_after_proj.w());
            var vertex_after_norm = vertex_after_proj.mul(norm);

            const vertex_after_screen = self.screen.vec4mulByMat4(vertex_after_norm);

            const coord_x: i16 = @floatToInt(i16, vertex_after_screen.x()); 
            const coord_y: i16 = @floatToInt(i16, vertex_after_screen.y()); 

            projected_vertices[idx].x=coord_x;
            projected_vertices[idx].y=coord_y;
        }     
    }  

    fn render_object(self: *Demo, render_target: RenderTarget, segments: []const Vec4, projected_vertices: []Coord, pal_entry: u8) void {

        for(segments) |segment| {
            const v1: Coord = projected_vertices[@floatToInt(usize, segment.x())];
            const v2: Coord = projected_vertices[@floatToInt(usize, segment.y())];
            const v3: Coord = projected_vertices[@floatToInt(usize, segment.z())];
            const v4: Coord = projected_vertices[@floatToInt(usize, segment.w())];

            shapes.drawLine(render_target, v1, v2, pal_entry);   
            shapes.drawLine(render_target, v2, v3, pal_entry);   
            shapes.drawLine(render_target, v3, v4, pal_entry);   
            shapes.drawLine(render_target, v4, v1, pal_entry);   
        }

        _ = self;
    }    
};
