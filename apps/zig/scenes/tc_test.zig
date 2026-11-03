// --------------------------------------------------------------------------
// TC TEST: HW 1.15.0's true-colour plane (FB_MODE_TRUECOLOR_FULL, RGB565, 400x280, borders
// open), shown doing what the palette modes cannot. One plane, mode 6:
//
//   1  GAMUT     all 65,536 565 colours on one screen
//   2  PLASMA    a 512x320 plasma (tens of thousands of colours) warped by the copper list:
//                an LBASE and an HSCROLL a line, no pixel written a frame (tc_test/plasma.zig)
//   3  COMPARE   one gradient as 565, as the best 256-colour palette and as 16 ST colours
//   4  RAMPS     R, G, B, grey: G has 64 steps, R and B 32
//   5  HUES      hue x value and hue x saturation
//   6  SKY       a radial gradient between two close colours: 565's banding worst case
//   7  DITHER    the same sky, plain beside 2x2 ordered dither
//   N / Space / Right   the next local picture,  P / Backspace / Left   the previous one
//   Escape              back to the menu
//
// The still views are painted once at init into cart RAM (tc_test/paint.zig) and copied into
// the plane on a key; the plasma is painted once into VRAM. Per frame the CPU only rebuilds the
// plasma's line list (zg.linelist: words that change), so the cart costs ~one plane a frame.
//
// Local pictures (Matt's own; not cleared to publish, so never in a committed cart): drop any
// Pillow-readable file or raw Falcon true-colour dump (.TG1/.GOD/headerless 320x200 or 384x240,
// big-endian 565) into prototypes/tc_test_art/, then
//     ZM_TC_ART=prototypes/tc_test_art ./build.sh --fast
// tools/tc_art.py converts them (sorted by name, cropped to 400x280, Falcon words only
// byte-swapped) and N / P step through them. A plain ./build.sh (the gate) leaves them out:
// rebuild that way before committing docs/demo-tc_test.*. apps/tc_test_check.mjs fails if a
// git-tracked cart carries any.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const paint = @import("tc_test/paint.zig");
const plasma = @import("tc_test/plasma.zig");
const art = @import("tc_test/art.zig");
const ZigOS = zg.ZigOS;
const tc = zg.tc;

pub const VIEWS = 7;
pub const PLASMA: u8 = 1;
const ROWS = paint.H;
const K_ESC: u32 = 0xE012; // demo_main.zig's code for Escape
const PX = paint.W * paint.H;

var lines: [ROWS]zg.linelist.Line = undefined;
// Still views painted at init (null: no cart RAM left, so a key paints straight into the plane).
var stills: [VIEWS]?tc.Fb = .{null} ** VIEWS;

pub const Demo = struct {
    os: *ZigOS,
    fb: tc.Fb,
    list: ?[]u32 = null,
    tex: ?plasma.Texture = null,
    view: u8 = 0,
    picture: ?usize = null, // a local picture shown instead of view
    fc: u32 = 0,
    wants_quit: bool = false,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        for (&zigos.lfbs) |*p| p.is_enabled = false;
        const plane = &zigos.lfbs[0];
        self.* = .{ .os = zigos, .fb = plane.setTruecolorPlane(.full) };
        plane.is_enabled = true;
        self.tex = plasma.build();
        self.list = zg.linelist.install(plane, ROWS, false); // after the VRAM buffers: hashable below it
        for (0..VIEWS) |v| stills[v] = paintStill(@intCast(v), zigos.system_font);
        art.announce();
        self.show(PLASMA);
    }

    /// Digits 1-7 from the host (mode = digit - 1).
    pub fn setShadeMode(self: *Demo, mode: u32) void {
        if (mode < VIEWS) self.show(@intCast(mode));
    }

    pub fn key(self: *Demo, cp: u32) void {
        switch (cp) {
            K_ESC => self.wants_quit = true,
            'n', 'N', ' ' => self.step(1),
            'p', 'P', 8 => self.step(art.count -| 1),
            else => {},
        }
    }

    // The board's glass sends the arrows (Direction: 2 Left, 3 Right).
    pub fn input(self: *Demo, dir: u8) void {
        if (dir == 3) self.step(1);
        if (dir == 2) self.step(art.count -| 1);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        self.fc +%= 1;
    }

    // The plasma's line list is the only per-frame work; a still view's list never changes.
    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        if (self.picture != null or self.view != PLASMA) return;
        const t = self.tex orelse return;
        for (&lines, 0..) |*l, y| l.* = plasma.line(t, @intCast(y), self.fc);
        self.commit();
    }

    // Local picture (current + by) mod count, from the first one when none is shown.
    fn step(self: *Demo, by: usize) void {
        if (art.count == 0) return;
        const i = if (self.picture) |p| (p + by) % art.count else 0;
        self.picture = i;
        art.show(self.fb, i);
        self.still();
    }

    fn show(self: *Demo, v: u8) void {
        self.view = v;
        self.picture = null;
        if (v == PLASMA) return;
        if (stills[v]) |s| copy(self.fb, s) else _ = paintInto(v, self.fb, self.os.system_font);
        self.still();
    }

    // A list showing the plane's own buffer straight: one LBASE on line 0, the counter runs on.
    fn still(self: *Demo) void {
        const plane = &self.os.lfbs[0];
        for (&lines, 0..) |*l, y| l.* = .{ .base = plane.lineAddr(0, @intCast(y)) };
        self.commit();
    }

    fn commit(self: *Demo) void {
        const l = self.list orelse return;
        _ = zg.linelist.build(l, &lines, .{ .plane = 0, .stride = 2 * paint.W, .colour_entry = null }) catch {};
    }
};

fn copy(dst: tc.Fb, src: tc.Fb) void {
    @memcpy(dst.pixels[0..PX], src.pixels[0..PX]);
}

// View v painted into cart RAM once; null for the plasma (VRAM) or when RAM is short.
fn paintStill(v: u8, font: []const u8) ?tc.Fb {
    if (v == PLASMA) return null;
    const words = zg.mem.alloc(u32, PX / 2) orelse return null;
    const fb = tc.Fb{ .pixels = @ptrCast(words.ptr), .w = paint.W, .h = paint.H, .stride = paint.W };
    _ = paintInto(v, fb, font);
    return fb;
}

fn paintInto(v: u8, fb: tc.Fb, font: []const u8) bool {
    switch (v) {
        0 => paint.gamut(fb, font),
        2 => paint.compare(fb, font),
        3 => paint.ramps(fb, font),
        4 => paint.hues(fb),
        5 => paint.sky(fb, font, false),
        6 => paint.sky(fb, font, true),
        else => return false,
    }
    return true;
}
