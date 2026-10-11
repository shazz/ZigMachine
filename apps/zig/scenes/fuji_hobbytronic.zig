// --------------------------------------------------------------------------
// FUJI HOBBYTRONIC: the Atari Fuji in 3D, with rasters through it, to an
// Atari 8-bit tune on the POKEY.
//
// Music: "Hobbytronic '92 - 1" by Stephan Duesterhoeft (Benjy), 1992, SAP
// TYPE B, 2:03 looped, from ASMA, the Atari SAP Music Archive
// (https://asma.atari.org/asma/Composers/Duesterhoeft_Stephan/Hobbytronic_92_1.sap),
// published in docs/music/ (Matt, 2026-10-10). Its own 6502 code drives the
// machine's POKEY; the screen asks for song 1 (zg.requestSongTune counts from 1).
//
// Written as a challenge for the FPGA SoC, whose cart CPU is an RV32IM at
// 100 MHz with no FPU, so the frame path has no floats at all:
//   - the logo (fuji_hobbytronic/mesh.zig) is the real Fuji, traced from the
//     logo by tools/gen_fuji_mesh.py and extruded: 138 vertices,
//     264 triangles; fixed.zig turns, projects, culls and lights it in Q14;
//   - logo.zig sorts the visible triangles far to near and fills each with
//     one hardware BLITTER triangle op;
//   - the colours running through the front cap are REAL rasters
//     (fuji_hobbytronic/raster.zig): one palette index, rewritten per scanline
//     by the plane's HBL handler, never bars drawn as pixels;
//   - a starfield, a title and a credits scroller (backdrop.zig) complete it.
// Every motion steps once a frame, so a frame's picture depends on its number
// alone. No keys of its own: Escape leaves, as on any screen without key().
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const fx = @import("fuji_hobbytronic/fixed.zig");
const logo = @import("fuji_hobbytronic/logo.zig");
const raster = @import("fuji_hobbytronic/raster.zig");
const backdrop = @import("fuji_hobbytronic/backdrop.zig");

pub const MUSIC = "Hobbytronic_92_1.sap";
pub const SONG: u8 = 1;

const PLANE = 0;
const CX = 160;
const CY = 92; // the logo's centre line, between the title and the scroller

const YAW_STEP = 3; // angle units a frame: a full turn in 341 frames
const TILT = 64; // the wobble's peak pitch, angle units (22.5 degrees)
const WOBBLE_STEP = 2; // a wobble every 512 frames
const BOB = 6; // pixels up and down, on the wobble's second harmonic
const SCROLL_SPEED = 2;

pub const Demo = struct {
    blitter: zg.Blitter,
    stars: backdrop.Stars,
    frames: u32,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.blitter = .{};
        self.blitter.init();
        self.stars.init();
        self.frames = 0;
        raster.offset = 0;
        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 32, .a = 255 });
        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.palette[backdrop.BG] = raster.st(0, 0, 1);
        fb.palette[backdrop.STAR + 0] = raster.st(2, 2, 3);
        fb.palette[backdrop.STAR + 1] = raster.st(4, 4, 5);
        fb.palette[backdrop.STAR + 2] = raster.st(7, 7, 7);
        fb.palette[backdrop.TITLE] = raster.st(7, 4, 1);
        fb.palette[raster.FRONT] = raster.FRONT_TAB[0];
        fb.palette[raster.BACK] = raster.BACK_TAB[0];
        fb.palette[raster.SCROLL] = raster.SCROLL_TAB[0];
        logo.sidePalette(fb);
        fb.setFrameBufferHBLHandler(0, raster.handler);
        fb.clearFrameBuffer(backdrop.BG);
        zg.requestSongTune(MUSIC, SONG); // a screen starts with its music
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt; // frame-stepped on purpose: see the header
        self.frames +%= 1;
        raster.offset +%= 1;
        self.stars.update();
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[PLANE];
        const f: i32 = @intCast(self.frames % (fx.STEPS * 64)); // keeps the angles small; both periods divide it
        self.blitter.clear(fb, backdrop.BG);
        self.stars.draw(fb);
        backdrop.title(zigos, fb);
        const wobble = f * WOBBLE_STEP;
        const pitch = (TILT * fx.sin(wobble)) >> fx.Q;
        const bob = (BOB * fx.sin(2 * wobble)) >> fx.Q;
        _ = logo.draw(fb, &self.blitter, f * YAW_STEP, pitch, CX, CY + bob);
        backdrop.scroller(zigos, fb, self.frames * SCROLL_SPEED);
    }
};
