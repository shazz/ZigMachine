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

const Vec3 = za.Vec3;
const Vec4 = za.Vec4;
const wf = zg.wireframe;

// The MAXI logo: a frame, the yellow letters and the red letters, each its own
// .obj (drawn in its own colour), centred in init().
const rect = zg.obj.parseWire(@embedFile("../assets/obj/maxi_rectangle.obj"));
const yellow = zg.obj.parseWire(@embedFile("../assets/obj/maxi_yellow.obj"));
const red = zg.obj.parseWire(@embedFile("../assets/obj/maxi_red.obj"));
var vertices_rectangle = wf.vec4s(rect.verts.len, rect.verts);
var vertices_yellow = wf.vec4s(yellow.verts.len, yellow.verts);
var vertices_red = wf.vec4s(red.verts.len, red.verts);

// Every object shares one pose per frame: spin X/Y/Z, then slide along x.
const Pose = struct { ax: f32, ay: f32, az: f32, tx: f32 };

fn posed(p: Pose, v: Vec4) Vec4 {
    return wf.rotateXYZ(v, p.ax, p.ay, p.az).add(Vec4.new(p.tx, 0.0, 0.0, 0.0));
}

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
    cam: wf.Camera = undefined,
    projected_vertices_rectangle: [rect.verts.len]Coord = undefined,
    projected_vertices_yellow: [yellow.verts.len]Coord = undefined,
    projected_vertices_red: [red.verts.len]Coord = undefined,
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

        for (&vertices_rectangle) |*v| v.* = v.add(Vec4.new(-1.2, -0.5, -0.0, 0.0));
        for (&vertices_yellow) |*v| v.* = v.add(Vec4.new(-1.2, -0.5, 0.35, 0.0));
        for (&vertices_red) |*v| v.* = v.add(Vec4.new(-1.2, -0.5, 0.35, 0.0));

        // set lines colors
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(2, Color{ .r = 0xf0, .g = 0x10, .b = 0x10, .a = 255 });
        fb.setPaletteEntry(3, Color{ .r = 0xf0, .g = 0xf0, .b = 0x10, .a = 255 });
        fb.setPaletteEntry(4, Color{ .r = 0xf0, .g = 0xf0, .b = 0xf0, .a = 255 });

        self.cam = .{
            .projection = za.perspective(40.0, 200.0 / 320.0, 1, 1000),
            .camera = za.camera(Vec3.new(0.0, 0.4, -5.0), 0, 0),
            .screen = za.screen(320, 200),
        };

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.pos_x += 0.06;
        const f_sin: f32 = @sin(self.pos_x) * 0.60; 

        const base_incr = 0.55;
        self.angle_x -= (base_incr * 1);
        self.angle_y -= (base_incr * 2);
        self.angle_z -= (base_incr * 4);

        const pose: Pose = .{ .ax = self.angle_x, .ay = self.angle_y, .az = self.angle_z, .tx = f_sin };
        self.cam.project(&vertices_rectangle, &self.projected_vertices_rectangle, pose, posed);
        self.cam.project(&vertices_yellow, &self.projected_vertices_yellow, pose, posed);
        self.cam.project(&vertices_red, &self.projected_vertices_red, pose, posed);

        _ = zigos;
        _ = elapsed_time;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.render_target.clearFrameBuffer(0);
        self.render_text();

        wf.drawEdges(self.render_target, &rect.edges, &self.projected_vertices_rectangle, 2, shapes.drawLine);
        wf.drawEdges(self.render_target, &yellow.edges, &self.projected_vertices_yellow, 3, shapes.drawLine);
        wf.drawEdges(self.render_target, &red.edges, &self.projected_vertices_red, 4, shapes.drawLine);

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
};
