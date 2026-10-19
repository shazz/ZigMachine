// --------------------------------------------------------------------------
// Buxton Bytes 2025 Fantasy Cracktro Challenge competition Atari ST/E
// Donut 2025 by Desire
//
// Music: Cerror
// Gfx: Jade
// Code: Tim
// original: https://fujiology.org/ST/D/DESIRE/2025DONT.ZIP
//
// Basically the DESIRE logo, a fhuge flat-shaded rotating torus, and a scrolling text.
// logo as png in assets/screens/desire/logo.png,
// font as png in assets/screens/desire/font.png,
// music as sndh in /home/matt/projects/ZigMachine/prototypes/sndh_lf/Cerror/Desire_Donut.sndh

// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;
const Console = zg.Console;
const Blitter = zg.Blitter;
const Vec2 = zg.BlitVec2;
const obj = zg.obj;
const convertU8ArraytoColors = zg.convertU8ArraytoColors;
const Scrolltext = zg.Scrolltext;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = zg.HEIGHT;
const WIDTH: u16 = zg.WIDTH;

pub const PHYSICAL_WIDTH: u16 = zg.PHYSICAL_WIDTH;
pub const PHYSICAL_HEIGHT: u16 = zg.PHYSICAL_HEIGHT;

const MODELS = [_][]const u8{
    @embedFile("../assets/obj/lowpoly_torus.obj"),
};

// logo
const logo_pal = convertU8ArraytoColors(@embedFile("../assets/screens/desire/logo_pal.dat"));
const logo_b = @embedFile("../assets/screens/desire/logo.raw");

// font
const SCROLL_TEXT = "       yo, scene lovers and cracktro dreamers! The DESIRE crew i scrashin' the party on the Atari ST-yeah, you heard right! While we're Amiga to the core,     ";
const SCROLL_CHAR_WIDTH = 8;
const SCROLL_CHAR_HEIGHT = 8;
const SCROLL_SPEED = 2;
const SCROLL_CHARS = " ! #$%&'()*+,-./0123456789:;<=>? ABCDEFGHIJKLMNOPQRSTUVWXYZ";
pub const NB_FONTS: u8 = (WIDTH / SCROLL_CHAR_WIDTH) + 1;
const SCROLL_TOP_POS = 180;

const font_pal = convertU8ArraytoColors(@embedFile("../assets/screens/desire/font.dat"));
const fonts_b = @embedFile("../assets/screens/desire/fon.raw");

// music
const MUSIC = "cerror.sndh";

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Demo = struct {
    colors: [2000]u8 = undefined,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        zg.requestSong(MUSIC);

        self.os = zigos;
        self.blitter.init();

        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;

        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        var j: u8 = 1;
        while (j < 255) : (j += 1) {
            fb.setPaletteEntry(j, Color{ .r = 0, .g = 0, .b = 255, .a = 255 - j });
        }

        // third plane
        fb = &zigos.lfbs[2];
        fb.is_enabled = true;
        fb.setPalette(font_pal);
        self.scrolltext = Scrolltext(NB_FONTS).init(fb.getRenderTarget(), fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 194, null, null, null);

        Console.log("demo init done!", .{});
    }

    fn loadModel(self: *Demo, m: u8) void {
        self.model = m;
        self.mesh.load(MODELS[m]);
        Console.log("obj: model {} -> {} verts, {} faces", .{ m, self.mesh.nverts, self.mesh.nfaces });
        self.programPalette();
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        self.ax += 0.019;
        self.ay += 0.027;
        self.az += 0.011;
        self.project();

        self.scrolltext.update();
    }

    pub fn render(self: *Demo, zigos: *ZigOS, time_elapsed: f32) void {
        const fb: *LogicalFB = &zigos.lfbs[0];
        const b = &self.blitter;

        b.clear(fb, 0);
        self.drawFlat(fb);

        self.scrolltext.target.clearFrameBuffer(0);
        self.scrolltext.render();

        // _ = zigos;
        // _ = self;
        _ = time_elapsed;
    }

    fn drawFlat(self: *Demo, fb: *LogicalFB) void {
        const b = &self.blitter;
        var order: [obj.MAX_FACES]u16 = undefined;
        self.sortFaces(&order);
        for (order[0..self.mesh.nfaces]) |f| {
            const t = self.mesh.faces[f];
            const shade: u8 = 1 + self.brightness(f);
            b.triangle(fb, self.screen[t.a], self.screen[t.b], self.screen[t.c], shade);
        }
    }

    // --- geometry ----------------------------------------------------------
    fn project(self: *Demo) void {
        const sx = @sin(self.ax);
        const cx = @cos(self.ax);
        const sy = @sin(self.ay);
        const cy = @cos(self.ay);
        const sz = @sin(self.az);
        const cz = @cos(self.az);
        for (self.mesh.verts[0..self.mesh.nverts], 0..) |p, i| {
            const y1 = p.y * cx - p.z * sx;
            const z1 = p.y * sx + p.z * cx;
            const x2 = p.x * cy + z1 * sy;
            const z2 = -p.x * sy + z1 * cy;
            self.pos[i] = .{ x2 * cz - y1 * sz, x2 * sz + y1 * cz, z2 };
            const zc = z2 + 100;
            self.screen[i] = .{
                .x = @intFromFloat(@as(f32, @floatFromInt(@divTrunc(WIDTH, 2))) + self.pos[i][0] * FOV / zc),
                .y = @intFromFloat(@as(f32, @floatFromInt(@divTrunc(HEIGHT, 2))) + self.pos[i][1] * FOV / zc),
            };
        }
    }
};
