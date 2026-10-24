// --------------------------------------------------------------------------
// THE CAREBEARS — COLORSHOCK 2, from The Cuddly Demos.
//   original: code TCB, music MAD MAX (Jochen Hippel)
//   CODEF HTML5 remake (screen 172) by AYOROS / Impact, MIT-licensed
//
// Ported from prototypes/codef/172/screen.js. What is on screen: the bouncing
// all-512-colours square field, the THE CAREBEARS logo, and one scrolltext in a
// strip that rides up and down a 1873-entry table. That is the whole screen.
//
// GEOMETRY. mycanvas is 680x400 = an ST 340x200 doubled, NOT 320x200 — every
// coordinate below is the original's halved, and the 20 extra columns are real:
// this is a TCB screen, so they are the SIDE BORDERS. The port therefore runs on
// the 400x280 OVERSCAN plane and maps the remake's 340x200 canvas onto it at
// (30, 40): canvas x 0..339 -> logical x -10..329 (10 px into each side border),
// canvas y 0..199 -> the visible band exactly. The remaining border rows are
// filled by extending the background pan, which costs nothing (see below).
//
// DELIBERATE DEPARTURES FROM THE REMAKE:
//  1. The fake AtariDecrunch depack intro (screen.js init()/init2()) is NOT
//     ported: ZigMachine has that look as a REAL depack effect (zx0.Fx.automation).
//  2. The background is not re-blitted per frame. go() redraws the whole
//     2492x1152 sheet every frame at a Lissajous position; we paint ONE pan
//     buffer at init and move the READ POINTER with setScroll() — one register
//     write, zero pixels.
//  3. mycanvas_anim (600x400) is created, drawn to mycanvas every frame and
//     never painted: a dead offscreen. Dropped.
//  4. The 512 colours are done the way TCB did them — a PALETTE PER SCANLINE
//     (see the HBL below) — instead of quantizing the field into 256 entries,
//     which measured a mean error of 15/255 on a picture whose whole point is
//     its colours.
//
//  5. ONE PLANE, not two (2026-10-23): the logo and the strip are drawn INTO the
//     panned buffer at the window's position, in the field's per-line palettes
//     (the plane table: tcb_colorshock/inkpal.zig). Plane 0 stays for the
//     hardware pan and its per-line palette.
//
// Everything else is the original's own numbers: the vbl increment of 0.8, the
// sin/cos amplitudes, the movescroll table lifted verbatim out of screen.js, the
// scrolltext slot arithmetic of lib/codef_scrolltext.js.
// --------------------------------------------------------------------------
const std = @import("std");

const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Console = zg.Console;

const field = @import("tcb_colorshock/field.zig");
const inkpal = @import("tcb_colorshock/inkpal.zig");
const strip = @import("tcb_colorshock/strip.zig");
const hbl = @import("tcb_colorshock/hbl.zig");

const movescroll_b = @embedFile("../assets/screens/tcb_colorshock/movescroll.dat");

// MUSIC. The remake plays Colorshock.ym, a register dump — deprecated here. The
// dump's own YM6 header names the tune "Cuddly Demos: Coloshock" by Jochen
// Hippel, and no SNDH carries that title; the match was found by playing every
// tune in Mad_Max/Demos/Cuddly_Demos/ and comparing register streams. Comic
// Bakery is IDENTICAL: registers 0..12 agree with the dump on all 9600 frames
// (r13 differs only because the dump writes $ff for "envelope not retriggered").
// So Colorshock's music is the Cuddly Demos' Comic Bakery tune. FLAG ~y, one
// subtune, peak 0.33 through apps/sndh_headless.mjs.
const MUSIC = "comic_bakery.sndh";

// Where the canvas sits on the 400x280 plane.
const OX: u16 = 30;
const OY: u16 = 40;

// The strip is blitted to the screen at (40, movescroll[pos_scroll]) => ST
// (20, movescroll/2), i.e. plane (OX+20, OY+movescroll/2).
const STRIP_X: u16 = OX + 20; // 50

// The logo. mylogo.setmidhandle() + draw(mycanvas,340,50) puts its top-left at
// canvas 2x (130,17); the artwork's own 2x grid is offset by a row, so its
// first 1x row lands on canvas 1x row 9.
const LOGO_W: u16 = 210;
const LOGO_H: u16 = 33;
const LOGO_X: u16 = OX + 65;
const LOGO_Y: u16 = OY + 9;

// screen.js: `if (pos_scroll>1872) pos_scroll=0` — the last index it ever reads,
// one short of the table's 1873 entries (the odd entries are never visited).
const MOVESCROLL_LAST: usize = 1872;

comptime {
    if (movescroll_b.len != (MOVESCROLL_LAST + 1) * 2) @compileError("movescroll.dat is not 1873 u16 entries");
    // The strip is drawn at OY + movescroll/2 with no runtime clamp, so prove
    // HERE that it stays on screen and below the logo: the logo's lines and the
    // strip's must never meet, or one line would need both inks' entries.
    @setEvalBranchQuota(20_000);
    var top: u16 = 0xFFFF;
    var bottom: u16 = 0;
    var i: usize = 0;
    while (i <= MOVESCROLL_LAST) : (i += 2) {
        top = @min(top, movescroll(i) >> 1);
        bottom = @max(bottom, movescroll(i) >> 1);
    }
    if (OY + bottom + strip.STRIP_H > zg.PHYSICAL_HEIGHT) @compileError("the scroll strip would run off the bottom of the plane");
    if (OY + top < LOGO_Y + LOGO_H) @compileError("the scroll strip would reach the logo's lines");
    // Ink drawn at the window's position stays inside the pan buffer.
    if (400 + STRIP_X + strip.STRIP_W > field.BUF_W or 400 + LOGO_X + LOGO_W > field.BUF_W) @compileError("ink past the buffer's right edge");
    if (field.TILE_H - 1 + OY + bottom + strip.STRIP_H > field.BUF_H) @compileError("ink past the buffer's bottom");
}

/// Where the ink was drawn in the pan buffer: put the field back there next frame.
const Drawn = struct { x: u16, row: u32, strip_y: u16 };

pub const Demo = struct {
    // NOTE: demo_main holds the cart as `undefined`, so a field's declared
    // default never runs. Every one of these is assigned in init().
    wave: field.Lissajous,
    pos_scroll: usize,
    strip_y: u16, // plane row the strip is drawn at this frame
    text: strip.Text,
    gpu: zg.Blitter,
    drawn: ?Drawn,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("tcb_colorshock: THE CAREBEARS / COLORSHOCK 2", .{});

        const bg: *LogicalFB = &zigos.lfbs[0];
        bg.is_enabled = true;
        field.pan_row = 0; // module state, so a re-entered scene must not inherit it
        field.pan_x = 0;
        bg.setOverscanScrollPlane(field.BUF_W, field.BUF_H);
        field.paintPanBuffer(bg);
        field.installRowPalette(bg, 0);
        for (inkpal.logo_colours, 0..) |c, i| bg.palette[inkpal.LOGO_FIRST + i] = c;
        hbl.strip_pal.reset();
        bg.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, hbl.panHbl);
        zigos.lfbs[1].is_enabled = false;

        self.gpu = .{};
        self.gpu.init();
        self.drawn = null;
        self.wave = .{ .x = 0, .y = 0 };
        self.pos_scroll = 0;
        self.strip_y = OY + (movescroll(0) >> 1);
        self.text.init();

        zg.requestSong(MUSIC);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        self.wave.pan(&zigos.lfbs[0]);

        // The table is read BEFORE the step, so the strip visits 0,2,...,1872.
        if (self.pos_scroll > MOVESCROLL_LAST) self.pos_scroll = 0;
        self.strip_y = OY + (movescroll(self.pos_scroll) >> 1);
        self.pos_scroll += 2;
        self.text.step();
    }

    // The window moved, so the ink moves inside the buffer: put the field back
    // where it was drawn last frame, then draw it at the window's position.
    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const bg: *LogicalFB = &zigos.lfbs[0];
        if (self.drawn) |d| {
            field.restore(&self.gpu, bg, d.x + LOGO_X, d.row + LOGO_Y, LOGO_W, LOGO_H);
            field.restore(&self.gpu, bg, d.x + STRIP_X, d.row + d.strip_y, strip.STRIP_W, strip.STRIP_H);
        }
        const x = field.pan_x;
        const row = field.pan_row;
        var v = field.rowView(bg, row + LOGO_Y);
        self.gpu.blitImage(&v, @intCast(x + LOGO_X), 0, &inkpal.logo_pixels, LOGO_W, 0, 0, LOGO_W, LOGO_H, 0);

        self.text.build();
        var gy: usize = 0;
        while (gy < strip.STRIP_H) : (gy += 1) {
            hbl.strip_pal.remapRow(gy, strip.row(gy), strip.accRow(gy));
        }
        hbl.strip_line = self.strip_y;
        v = field.rowView(bg, row + self.strip_y);
        self.gpu.blitImage(&v, @intCast(x + STRIP_X), 0, &strip.pixels, strip.STRIP_W, 0, 0, strip.STRIP_W, strip.STRIP_H, 0);
        self.drawn = .{ .x = x, .row = row, .strip_y = self.strip_y };
    }
};

fn movescroll(i: usize) u16 {
    return std.mem.readInt(u16, movescroll_b[i * 2 ..][0..2], .little);
}
