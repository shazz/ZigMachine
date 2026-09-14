// --------------------------------------------------------------------------
// The Union Demo (1989), TNT1: the TNT-Crew's "Starballs", ported from shazz's
// melonJS "Union Demo HTML5 Remake" 0.9.8 (screens/tnt1/screen.js, loader.js).
// Program by Hexogen, graphics by ES, Pandora composed by Rob Hubbard and
// converted by Mad Max: all The Union's.
//
// On screen (screen.js:160-190), one plane, one palette:
//   - #000040, the TNT logo at canvas (224,8);
//   - a CODEF ballfield of 60 balls (keys 1..0: 100..550) flying at the viewer,
//     blue tiles on top of everything but the logo and the scroller;
//   - the scroller at canvas row 384, speed 3, in the logo's dark red;
//   - the same ballfield stepped AGAIN in red, landing 'source-atop' on a canvas
//     holding only the logo and the scroller: red balls inside those shapes.
// ballsfield.draw() runs twice a draw(), so the red balls are one step (4 z
// units, not 2) ahead of the blue ones, and every ball moves twice a frame.
//
// As palette work: the atop canvas's opaque pixels are exactly the ink (2) and
// the red tiles' entries, so pass 1 draws blue only OUTSIDE that set and pass 2
// draws red only INSIDE it (blit's .select ink). Drawing order within a pass is
// the field's, later balls on top.
//
// Geometry: a 640x400 canvas, every PNG pixel-doubled on the (0,0) grid, so it
// halves onto 320x200. The balls sit at fractional canvas positions, which
// Chrome draws bilinearly; here each snaps to the nearest ST pixel,
// round(c / 2), the closest a palette plane gets (apps/union_tnt1_replay.mjs).
// The Math.random of codef_bobfield.js is xorshift32 from a fixed seed.
//
// Loading: the remake's TEX loader panel (loader.js) is the REAL depack here
// (fx = tex_loader, build.zig). Its "PRESS SPACE" wait is not kept.
// Leaving: Escape or Space (screen.js:77-81) goes back to the hub. The remake
// carries the menu's scroller position into the screen (jsApp.mainscrollerPos);
// the hub is another cart here, so the scroller starts at the text's beginning.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const hw = @import("hardware");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const blit = zg.blit;
const ballfield = zg.ballfield;
const DepackFx = @import("depackers").depack_fx.Runner(zg, null);
const packed_assets = @import("packed_assets");

// The remake plays data/music/Pandora.ym ("U_STARBL.BIN"); this is Mad Max's
// Union Demo Pandora from the SNDH archive (one subtune, FLAG ~y).
const MUSIC = "union/pandora.sndh";
const HUB = "union_demo";
const K_ESC: u32 = 0xE012;
// tnt1.bin is 20,016 bytes: at the slowest pacing, 1 byte a line, the panel
// assembles over 72 frames (the remake's takes 99).
const DEPACK_BYTES_PER_LINE = 1;

/// jsApp.scrolltext (main.js:50), shared with the hub.
const TEXT = @embedFile("../assets/screens/union_demo/scrolltext.txt");
/// tools/private_tools/union_tnt1_assets.py: 0 transparent, 1 #000040,
/// 2 #800000 (logo, font), 3..10 blue balls, 11..17 red balls.
const palette = zg.convertU8ArraytoColors(@embedFile("../assets/screens/union_tnt1/pal.dat"));
const BG: u8 = 1;
const INK: u8 = 2;
const RED_FIRST: u8 = 11;
const RED_LAST: u8 = 17;

const LOGO_W = 78; // logo.png 156x80
const LOGO_H = 40;
const LOGO_X = 112; // logo.draw(maincanvas, 224, 8)
const LOGO_Y = 4;
const FONT_W = 256; // fonts.png 512x64, initTile(32,16,32)
const FONT_H = 32;
const GLYPH_W = 16;
const GLYPH_H = 8;
const FONT_COLS = 16;
const FIRST_CHAR = 32;
const SCROLL_Y = 192; // scrollcanvas.draw(ballcanvas, 0, 384)
const LETTERS = 22; // wide = ceil(640/32)+1 = 21, letters 0..wide
const GLYPH_C: i32 = 32;
const SPEED_C: i32 = 3; // scrolltext.init(scrollcanvas, font, 3)
const SHEET_W = 272; // balls.png 544x32, initTile(32,32): 17 tiles
const TILE = 16;
const TILES = 17;
const TOTAL = LOGO_W * LOGO_H + FONT_W * FONT_H + 2 * SHEET_W * TILE;

comptime {
    @setEvalBranchQuota(4 * TEXT.len + 1000);
    for (TEXT) |c| if (c < FIRST_CHAR or c >= FIRST_CHAR + FONT_COLS * 4) @compileError("scrolltext character outside fonts.png");
}

/// new ballfield(ballcanvas, n, 2.0, 640,400, 640/2,400/2, 60,0,0, balls, 17)
const FIELD = ballfield.Params{ .w = 640, .h = 400, .centx = 320, .centy = 200, .speed = 2.0, .ratio = 60, .tiles = TILES };
const SEED: u32 = 0x1D872B41; // apps/union_tnt1_replay.mjs SEED
const START_BALLS = 60;
const MAX_BALLS = 550;

/// The ballcanvas pixels 'source-atop' keeps: logo and scroller ink, red balls.
const atop_canvas: [256]bool = blk: {
    var s = [_]bool{false} ** 256;
    s[INK] = true;
    for (RED_FIRST..RED_LAST + 1) |i| s[i] = true;
    break :blk s;
};

/// One drawn tile, already on the ST grid.
const Spot = struct { x: i16, y: i16, tile: u8 };
const Pass = struct { spots: [MAX_BALLS]Spot, n: usize };
/// The balls and their two draw lists, ~29 KB: in free cart RAM after the
/// depacked images, since a module-scope array is written into the cart's data
/// segment as zeros, `undefined` or not.
const Work = struct { balls: [MAX_BALLS]ballfield.Ball, passes: [2]Pass };

// Module scope: the runner needs a stable address.
var depack: DepackFx = undefined;

const Images = struct { logo: blit.Image, font: blit.Image, blue: blit.Image, red: blit.Image };
const Phase = enum { loading, running, failed };

pub const Demo = struct {
    phase: Phase,
    images: Images,
    work: *Work,
    field: ballfield.Field,
    random: ballfield.XorShift32,
    nb_balls: usize,
    wanted: usize, // a number key's count, applied by the next update
    ring: zg.scrollring.Ring(i32, LETTERS),
    leave: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.phase = .failed;
        self.leave = false;
        self.field = ballfield.Field.init(FIELD);
        self.random = ballfield.XorShift32.init(SEED);
        self.ring = zg.scrollring.Ring(i32, LETTERS).init(TEXT, (LETTERS - 1) * GLYPH_C, GLYPH_C);
        const ram = freeRam(TOTAL + @alignOf(Work) + @sizeOf(Work)) orelse return fail("no free RAM to depack into");
        const buf = ram[0..TOTAL];
        self.work = @ptrFromInt(std.mem.alignForward(usize, @intFromPtr(buf.ptr) + TOTAL, @alignOf(Work)));
        for (&self.work.passes) |*p| p.n = 0;
        self.spawn(START_BALLS); // the constructor's field
        if (!depack.start(zigos, packed_assets.union_tnt1, buf, DEPACK_BYTES_PER_LINE))
            return fail("packed image unreadable");
        self.images = split(buf);
        self.phase = .loading;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.phase == .loading) switch (depack.frame(zigos)) {
            .more => return,
            .done => self.start(zigos), // and this frame is the screen's first
            .failed => {
                self.phase = .failed;
                return fail("depack failed");
            },
        };
        if (self.phase != .running) return;
        if (self.wanted != self.nb_balls) self.spawn(self.wanted); // update()
        _ = self.ring.stepCount(SPEED_C); // draw(): the scroller moves...
        for (&self.work.passes) |*p| self.step(p); // ...and the field steps twice
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.phase != .running) return;
        const dst = blit.Dst.plane(&zigos.lfbs[0]);
        @memset(dst.buf, BG);
        blit.blit(dst, self.images.logo, null, LOGO_X, LOGO_Y, 0, .copy);
        for (self.ring.x, self.ring.c) |x, c| {
            const g: usize = c - FIRST_CHAR;
            const part = blit.Rect{ .x = g % FONT_COLS * GLYPH_W, .y = g / FONT_COLS * GLYPH_H, .w = GLYPH_W, .h = GLYPH_H };
            blit.blit(dst, self.images.font, part, @divFloor(x + 1, 2), SCROLL_Y, 0, .copy); // round(x/2)
        }
        drawPass(dst, &self.work.passes[0], self.images.blue, false);
        drawPass(dst, &self.work.passes[1], self.images.red, true);
    }

    /// Host input ids: 5 fire, 6 back.
    pub fn input(self: *Demo, dir: u8) void {
        if (dir == 6 or (dir == 5 and self.phase == .running)) self.leave = true;
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC or (cp == ' ' and self.phase == .running)) self.leave = true;
        if (self.phase != .running) return;
        if (cp == '0') self.wanted = 550;
        if (cp >= '1' and cp <= '9') self.wanted = 50 + 50 * @as(usize, cp - '0'); // '1' 100 .. '9' 500
    }

    pub fn pollCart(self: *Demo) i32 {
        if (!self.leave) return 0;
        self.leave = false;
        return 1;
    }

    pub fn cartTag(self: *Demo) []const u8 {
        _ = self;
        return HUB;
    }

    fn start(self: *Demo, zigos: *ZigOS) void {
        const fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPalette(palette);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        zg.requestSong(MUSIC); // onResetEvent
        self.phase = .running;
    }

    /// new ballfield(...): `n` balls from the next 3n random numbers.
    fn spawn(self: *Demo, n: usize) void {
        for (self.work.balls[0..n]) |*b| b.* = self.field.spawn(self.random.three());
        self.nb_balls = n;
        self.wanted = n;
    }

    /// One ballsfield.draw(): what it draws, snapped to the ST grid.
    fn step(self: *Demo, pass: *Pass) void {
        pass.n = 0;
        for (self.work.balls[0..self.nb_balls]) |*b| {
            const d = self.field.step(b) orelse continue;
            if (d.tile >= TILES) continue; // drawTile past the one-row sheet draws nothing
            pass.spots[pass.n] = .{ .x = toSt(d.x), .y = toSt(d.y), .tile = @intCast(d.tile) };
            pass.n += 1;
        }
    }
};

fn drawPass(dst: blit.Dst, pass: *const Pass, sheet: blit.Image, atop: bool) void {
    const ink = blit.Ink{ .select = .{ .set = &atop_canvas, .inside = atop } };
    for (pass.spots[0..pass.n]) |s| {
        const part = blit.Rect{ .x = @as(usize, s.tile) * TILE, .y = 0, .w = TILE, .h = TILE };
        blit.blit(dst, sheet, part, s.x, s.y, 0, ink);
    }
}

/// Canvas x or y (strictly inside 640x400) to the nearest ST pixel: Math.round(c/2).
fn toSt(c: f64) i16 {
    return @intFromFloat(@floor(c / 2 + 0.5));
}

fn split(buf: []const u8) Images {
    const font_at = LOGO_W * LOGO_H;
    const blue_at = font_at + FONT_W * FONT_H;
    const red_at = blue_at + SHEET_W * TILE;
    return .{
        .logo = blit.Image.init(buf[0..font_at], LOGO_W),
        .font = blit.Image.init(buf[font_at..blue_at], FONT_W),
        .blue = blit.Image.init(buf[blue_at..red_at], SHEET_W),
        .red = blit.Image.init(buf[red_at..TOTAL], SHEET_W),
    };
}

fn fail(why: []const u8) void {
    zg.Console.log("union_tnt1: {s}", .{why});
}

/// `len` bytes of the cart's RAM window above its statics and stack.
fn freeRam(len: usize) ?[]u8 {
    if (hw.hwRamFree() < len) return null;
    const base: usize = hw.hwRamBase() + hw.hwRamUsed();
    return @as([*]u8, @ptrFromInt(base))[0..len];
}
