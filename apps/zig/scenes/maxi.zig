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
const RenderTarget = zg.RenderTarget;
const RenderBuffer = zg.RenderBuffer;
const Resolution = zg.Resolution;

const Text = zg.Text;
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
// Count Zero, "3D Mania" from the Decade Demo (1990) — the demo's own 3D
// screen, which is what MAXI draws.
const MUSIC = "decade_3d_mania.sndh";

// scrolltext
const fonts_b = @embedFile("../assets/screens/reps/font.raw");
const fonts_chars = " ! #$%&'()*+,-./0123456789:;<=>? ABCDEFGHIJKLMNOPQRSTUVWXYZ";

// palettes
const font_pal = convertU8ArraytoColors(@embedFile("../assets/screens/reps/font_pal.dat"));

const Vec2 = za.Vec2;
const Vec3 = za.Vec3;
const Vec4 = za.Vec4;
const Mat4 = za.Mat4;

var vertices_rectangle = [_]Vec4{
        Vec4.new(  -0.02,      -0.02,     0,  1.0),
        Vec4.new(  2.40,     -0.02,     0,  1.0),
        Vec4.new( 2.40,      0.60,     0,  1.0),
        Vec4.new( -0.02,       0.60,     0,  1.0),
};

const segments_rectangle = [_]Vec2{
        Vec2.new(0, 1),
        Vec2.new(1, 2),
        Vec2.new(2, 3),
        Vec2.new(3, 0),
};

var vertices_yellow = [_]Vec4{
        Vec4.new(  0, 0.58, -0.10, 1.0),
        Vec4.new(  0,  0, -0.10, 1.0),
        Vec4.new( 0.40,  0.0, -0.30, 1.0),
        Vec4.new( 0.40, 0.30, -0.30, 1.0),
        Vec4.new(  0.09, 0.30, -0.13, 1.0),
        Vec4.new(  0.20, 0.30, -0.19, 1.0),
        Vec4.new(  0.40,  0.58, -0.30, 1.0),
    
        Vec4.new(  0.45, 0.58, -0.10, 1.0),
        Vec4.new(  0.45, 0.0, -0.10, 1.0),
        Vec4.new(  0.85, 0.0, -0.30, 1.0),
        Vec4.new(  0.85, 0.30, -0.30, 1.0),
        Vec4.new(  0.54, 0.30, -0.13, 1.0),
    
        Vec4.new(  0.97-0.13, 0.0, -0.10, 1.0),
        Vec4.new(  1.20-0.13, 0.0, -0.20, 1.0),
        Vec4.new(  1.10-0.13, 0.0, -0.155, 1.0),
        Vec4.new(  1.10-0.13, 0.58, -0.155, 1.0),
        Vec4.new(  0.97-0.13, 0.58, -0.10, 1.0),
        Vec4.new(  1.20-0.13, 0.58, -0.20, 1.0),
    
        Vec4.new(  1.33-0.10, 0.58, -0.10, 1.0),
        Vec4.new(  1.53-0.10, 0.0, -0.15, 1.0),
        Vec4.new(  1.73-0.10, 0.58, -0.30, 1.0),
        Vec4.new(  1.43-0.10, 0.30, -0.125, 1.0),
        Vec4.new(  1.63-0.10, 0.30, -0.225, 1.0),
    
        Vec4.new(  1.81, 0.0, -0.10, 1.0),
        Vec4.new(  2.14, 0.0, -0.30, 1.0),
        Vec4.new(  1.98, 0.0, -0.205, 1.0),
        Vec4.new(  1.98, 0.58, -0.205, 1.0),
};

const segments_yellow = [_]Vec2{
        Vec2.new(0,  1 ),
        Vec2.new(1,  2 ),
        Vec2.new(2,  3 ),
        Vec2.new(3,  4 ),
        Vec2.new(5,  6 ),
    
        Vec2.new(7,  8 ),
        Vec2.new(8,  9 ),
        Vec2.new(9,  10 ),
        Vec2.new(10,  11 ),
    
        Vec2.new(12,  13 ),
        Vec2.new(14,  15 ),
        Vec2.new(16,  17 ),
    
        Vec2.new(18,  19 ),
        Vec2.new(19,  20 ),
        Vec2.new(21,  22 ),

        Vec2.new(23,  24 ),
        Vec2.new(25,  26 ),
};

var vertices_red = [_]Vec4{
        Vec4.new(  0.60,  0.58,  -0.30, 1.0),
        Vec4.new(  0.20,  0.58,  -0.10, 1.0),
        Vec4.new(  0.20,   0.0,  -0.10, 1.0),
        Vec4.new(  0.60,   0.0,  -0.30, 1.0),
        Vec4.new(  0.20,  0.30,  -0.10, 1.0),
        Vec4.new(  0.50,  0.30,  -0.25, 1.0),
    
        Vec4.new(  1.05, 0.58,  -0.30, 1.0),
        Vec4.new(  0.65,  0.58,  -0.10, 1.0),
        Vec4.new(  0.65,   0.0,  -0.10, 1.0),
    
        Vec4.new(  1.48, 0.58,  -0.30, 1.0),
        Vec4.new(  1.10,  0.58,  -0.10, 1.0),
        Vec4.new(  1.10,   0.0,  -0.10, 1.0),
        Vec4.new(  1.48,   0.0,  -0.30, 1.0),
    
        Vec4.new(  1.53, 0.58,  -0.10, 1.0),
        Vec4.new(  1.53,  0.0,  -0.10, 1.0),
        Vec4.new(  1.93,   0.58,  -0.30, 1.0),
        Vec4.new(  1.93,   0.0,  -0.30, 1.0),
    
        Vec4.new(  1.98, 0.58,  -0.10, 1.0),
        Vec4.new(  2.38,  0.58,  -0.30, 1.0),
        Vec4.new(  2.38,   0.30,  -0.30, 1.0),
        Vec4.new(  1.98,   0.30,  -0.10, 1.0),
        Vec4.new(  1.98,   0.0,  -0.10, 1.0),
        Vec4.new(  2.38,   0.0,  -0.30, 1.0),   
};

const segments_red = [_]Vec2{
        Vec2.new(0,  1),
        Vec2.new(1,  2),
        Vec2.new(2,  3),
        Vec2.new(4,  5),
    
        Vec2.new(6,  7),
        Vec2.new(7,  8),
    
        Vec2.new(9,  10),
        Vec2.new(10,  11),
        Vec2.new(11,  12),
    
        Vec2.new(13,  14),
        Vec2.new(14,  15),
        Vec2.new(15,  16),
    
        Vec2.new(17,  18),
        Vec2.new(18,  19),
        Vec2.new(19,  20),
        Vec2.new(20,  21),
        Vec2.new(21,  22),
};

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------
var overcan_buffer = [_]u8{0} ** (320 * 280);
var render_buffer: RenderBuffer = .{ .buffer = &overcan_buffer, .width = 320, .height = 280 };   

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
fn handler_vertical_borders(fb: *LogicalFB, zigos: *ZigOS, line: u16, column: u16) void {
    _ = zigos;
    _ = column;

    // Overscan plane: this per-plane HBL fires on PHYSICAL lines 0..279. MAXI's
    // content is 320-wide (no side borders), so open only the TOP and BOTTOM borders
    // by flickering the resolution register in those bands (see docs/HW_API.md). The
    // frame content is blitted into the plane in render() with a +40 x offset.
    if (line < 40 or line >= 240) fb.flickerBorder();
}

pub const Demo = struct {
  
    name: u8 = 0,
    projection: Mat4 = undefined,
    camera: Mat4 = undefined,
    screen: Mat4 = undefined,
    projected_vertices_rectangle: [4]Coord = undefined,
    projected_vertices_yellow: [30]Coord = undefined,
    projected_vertices_red: [30]Coord = undefined,
    angle_y: f32 = 0.0,
    angle_x: f32 = 0.0,
    angle_z: f32 = 0.0,
    text: Text = undefined,
    render_target: RenderTarget = undefined,
    pos_x: f32 = 0,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // Nothing happens until the user turns sound on — the request just waits.
        zg.requestSong(MUSIC);

        // only one plane needed
        var fb: *LogicalFB = &zigos.lfbs[0];

        fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setOverscanBuffer(); // 400×280 plane; top/bottom borders opened via the trick
        fb.setPaletteEntry(0, Color{ .r=0, .g=0, .b=0, .a=0});
        fb.setPaletteEntry(1, Color{ .r=0, .g=0, .b=255, .a=255});

        // HBL: open the top/bottom borders (must fire at the magic column)
        fb.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, handler_vertical_borders);

        // create text buffer
        self.render_target = .{ .render_buffer = &render_buffer };  
        self.render_target.clearFrameBuffer(0); 

        self.text.init(self.render_target, fonts_b, fonts_chars, 8, 8);

        var i: usize = 0;
        while(i < vertices_rectangle.len) : ( i += 1) {
            vertices_rectangle[i] = vertices_rectangle[i].add(Vec4.new(-1.2, -0.5, -0.0, 0.0));
        }
        i = 0;
        while(i < vertices_yellow.len) : ( i += 1) {
            vertices_yellow[i] = vertices_yellow[i].add(Vec4.new(-1.2, -0.5, 0.35, 0.0));
        }
        i = 0;
        while(i < vertices_red.len) : ( i += 1) {
            vertices_red[i] = vertices_red[i].add(Vec4.new(-1.2, -0.5, 0.35, 0.0));
        }                     

        // set lines colors
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(2, Color{ .r = 0xf0, .g = 0x10, .b = 0x10, .a = 255 });
        fb.setPaletteEntry(3, Color{ .r = 0xf0, .g = 0xf0, .b = 0x10, .a = 255 });
        fb.setPaletteEntry(4, Color{ .r = 0xf0, .g = 0xf0, .b = 0xf0, .a = 255 });

        self.projection = za.perspective(40.0, 200.0 / 320.0, 1, 1000);
        self.camera = za.camera(Vec3.new(0.0, 0.4, -5.0), 0, 0);
        self.screen = za.screen(320, 200);   

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.pos_x += 0.06;
        const f_sin: f32 = @sin(self.pos_x) * 0.60; 

        const base_incr = 0.55;
        self.angle_x -= (base_incr * 1);
        self.angle_y -= (base_incr * 2);
        self.angle_z -= (base_incr * 4);

        self.transform_object(self.angle_x, self.angle_y, self.angle_z, f_sin, &vertices_rectangle, &self.projected_vertices_rectangle);
        self.transform_object(self.angle_x, self.angle_y, self.angle_z, f_sin, &vertices_yellow, &self.projected_vertices_yellow);
        self.transform_object(self.angle_x, self.angle_y, self.angle_z, f_sin, &vertices_red, &self.projected_vertices_red);

        _ = zigos;
        _ = elapsed_time;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.render_target.clearFrameBuffer(0);
        self.render_text();

        self.render_object(&segments_rectangle, &self.projected_vertices_rectangle, 2);
        self.render_object(&segments_yellow, &self.projected_vertices_yellow, 3);
        self.render_object(&segments_red, &self.projected_vertices_red, 4);

        // Blit the 320-wide overscan buffer into the 400-wide plane, centred (x+40) so
        // the visible window lines up; side borders stay closed (black).
        const fb = &zigos.lfbs[0];
        const pw: usize = zg.PHYSICAL_WIDTH;
        const ph: usize = zg.PHYSICAL_HEIGHT;
        const vw: usize = WIDTH;
        const border: usize = zg.OVERSCAN_MAGIC_X;
        var y: usize = 0;
        while (y < ph) : (y += 1) {
            var x: usize = 0;
            while (x < vw) : (x += 1) fb.fb[y * pw + x + border] = overcan_buffer[y * vw + x];
        }

        _ = elapsed_time;
    }

    fn render_text(self: *Demo) void {

        self.text.render("****************************************",0, 0 * 8, null);
        self.text.render(" **   THE REPLICANTS AND ST AMIGOS   ** ",0, 1 * 8, null);
        self.text.render("    **   BRING YOU AN HOT STUFF   **    ",0, 2 * 8, null);
        self.text.render("       **************************       ",0, 3 * 8, null);
        
        self.text.render("   SAVAGELY BROKEN AN TRAINED BY MAXI",   0, 5 * 8, null);
        self.text.render("  ------------------------------------",  0, 6 * 8, null);
        self.text.render("  DIS BOOT WAS ALSO FAST CODED BY MAXI",  0, 7 * 8, null);
        self.text.render(" --------------------------------------", 0, 8 * 8, null);
        
        self.text.render("       COPY IN 2 SIDES 10 SECTORS",       0, 10 * 8, null);
        self.text.render("   THE MAGIC KEY FOR THE TRAINER IS *",   0, 11 * 8, null);
        self.text.render("SORRY FOR DIS LITTLE LAME CODE ,COZ THAT",0, 12 * 8, null);
        self.text.render("IS NOT MY BEST 3D LINE ROUT ,SO FAR NOT.",0, 13 * 8, null);
        self.text.render("THAT IS MY SHORTER ONE ! BUT IN 3 PLANES",0, 14 * 8, null);
        self.text.render("THE GOOD IS RATHER MY UPPER BORDER ROUT!",0, 15 * 8, null); 
        
        self.text.render("VERY SPECIAL REGARDS GO TO :",            0, 19 * 8, null);
        self.text.render(" THOR - AVB - ST WAIKIKI- MINIMAX - ZAE", 0, 20 * 8, null);
        self.text.render(" MAD VISION  - FUZION - LITTLESWAP -FOF", 0, 21 * 8, null);
        self.text.render("  BAD BOYS - MCA - ACB - THE REDUCTORS",  0, 22 * 8, null);
        self.text.render("  RCA AND ALL THE MEMBERS OF THE UNION",  0, 23 * 8, null);
        
        self.text.render("I SEND THE NORMAL GREETINGS TO :",       0, 25 * 8, null);
        self.text.render(" ST CONNEXION-IMAGINA-PHALANC-FF-TELLER",0, 26 * 8, null);
        self.text.render(" 2 LIVE CREW-PENDRAGONS-DRAGON-FRAISINE",0, 27 * 8, null);
        self.text.render(" DIMITRI-EQUINOX-TGE-SEWER SOFT-ACF-BMT",0, 28 * 8, null);
        self.text.render(" MEDWAY BOYS-OVR-MCS-TDA-LOST BOYS-NEXT",0, 29 * 8, null);
        self.text.render(" ULM-PARADOX-SYNC-OMEGA-INNER CIRCLE-MU",0, 30 * 8, null);

        self.text.render("ENJOY THE VIOLENCE..THE REPLICANTS RULEZ",0,32 * 8, null);
        self.text.render("****************************************",0,33 * 8, null);

    }

    fn transform_object(self: *Demo, angle_x: f32, angle_y: f32, angle_z: f32, trans_x: f32, vertices: []Vec4, projected_vertices: []Coord) void {

        for(vertices, 0..) |vertex, idx| {

            const rot_matx = Mat4.fromEulerAngles(Vec3.new(angle_x, 0, 0));
            const vertex_after_rotx = rot_matx.vec4mulByMat4(vertex);

            const rot_maty = Mat4.fromEulerAngles(Vec3.new(0, angle_y, 0));
            const vertex_after_roty = rot_maty.vec4mulByMat4(vertex_after_rotx);

            const rot_matz = Mat4.fromEulerAngles(Vec3.new(0, 0, angle_z));
            const vertex_after_rotz = rot_matz.vec4mulByMat4(vertex_after_roty); 

            const translated_vertex = vertex_after_rotz.add(Vec4.new(trans_x, 0.0, 0.0, 0.0));           

            const vertex_after_cam = self.camera.vec4mulByMat4(translated_vertex);
            const vertex_after_proj = self.projection.vec4mulByMat4(vertex_after_cam);
                    
            const norm = Vec4.set(1/vertex_after_proj.w());
            const vertex_after_norm = vertex_after_proj.mul(norm);

            const vertex_after_screen = self.screen.vec4mulByMat4(vertex_after_norm);

            const coord_x: i16 = @as(i16, @intFromFloat(vertex_after_screen.x())); 
            const coord_y: i16 = @as(i16, @intFromFloat(vertex_after_screen.y())); 

            projected_vertices[idx].x=coord_x;
            projected_vertices[idx].y=coord_y;
        }     
    }  

    fn render_object(self: *Demo, segments: []const Vec2, projected_vertices: []Coord, pal_entry: u8) void {

        for(segments) |segment| {
            const v1: Coord = projected_vertices[@as(usize, @intFromFloat(segment.x()))];
            const v2: Coord = projected_vertices[@as(usize, @intFromFloat(segment.y()))];

            shapes.drawLine(self.render_target, v1, v2, pal_entry);   
        }
    }

};
