// --------------------------------------------------------------------------
// THE GNOMES GROUP "BB25": the frame loop (the original's main loop $13974).
// gnomes.zig carries the port notes. One overscan plane holds everything:
//
//   rasters.zig  colour 0 + colour 1 per line: two copper slots, borders open
//   logo.zig     the 36 logo lines, each at its own x every frame (sway/shear)
//   vu.zig       the three VU meters under the logo (YM registers 10/9/8)
//   tty.zig      the 13 typed pages
//   scroller.zig the big 32x25 scroller, 8 px a frame
//   SpongeBob    drawn once (his regs 2..7 below line SPLIT are the scroller's)
//
// Frame n here is the original's loop n: its screen buffer as loop n leaves it,
// with the raster list loop n-1 built (rasters.zig). No float anywhere.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const blit = zg.blit;
const copper = zg.copper;

const A = @import("assets.zig");
pub const rasters = @import("rasters.zig");
pub const logo = @import("logo.zig");
pub const vu = @import("vu.zig");
pub const tty = @import("tty.zig");
pub const scroller = @import("scroller.zig");

/// David Whittaker's "Custodian", the SNDH the intro embeds (Grazey's rip, 6 subtunes, F1-F6).
/// The SNDH archive's copy is played: same periods, but the embedded rip leaves subtune 3 silent here.
pub const MUSIC = "custodian.sndh";
pub const PLANE = 0;

const K_F1: u32 = 0xE001;
const K_F6: u32 = 0xE006;
const K_ESC: u32 = 0xE012;
const K_SPACE: u32 = ' '; // the original leaves on SPACE ($13D0E)
const DIR_BACK: u8 = 6;

pub var wants_quit = false;
pub var frame: u32 = 0;
pub var ym: [16]u8 = [_]u8{0} ** 16; // the YM mirror as this frame's VU read it

fn installPalette(fb: anytype) void {
    for (A.LOGO_PAL, 2..) |w, i| fb.palette[i] = A.st(w);
    for (A.SBOB_PAL[6..], 8..) |w, i| fb.palette[i] = A.st(w); // regs 8..15, shared
    for (A.SBOB_PAL[0..6], A.SBOB_LO..) |w, i| fb.palette[i] = A.st(w);
    for (A.SCROLL_PAL, A.SCROLL_LO..) |w, i| fb.palette[i] = A.st(w);
}

/// SpongeBob at (176, 80) ($13912: screen + $3258), opaque as the original's longword copy.
fn drawSpongeBob(d: blit.Dst) void {
    const screen = d.window(A.X0, A.Y0, 320, A.LINES);
    const img = blit.Image.init(A.sbob_raw, 144);
    var map: [256]u8 = undefined;
    for (&map, 0..) |*e, i| e.* = @truncate(i);
    const split = A.SPLIT - 80;
    for ([2]u8{ A.SBOB_LO, A.SCROLL_LO }, 0..) |lo, half| {
        for (2..8) |i| map[i] = lo + @as(u8, @intCast(i - 2));
        const y0: usize = if (half == 0) 0 else split;
        const h: usize = if (half == 0) split else 158 - split;
        blit.blit(screen, img, .{ .x = 0, .y = y0, .w = 144, .h = h }, 176, @intCast(80 + y0), null, .{ .lut = &map });
    }
}

pub const Demo = struct {
    pub fn init(self: *Demo, zigos: *ZigOS) void {
        _ = self;
        wants_quit = false;
        frame = 0;
        ym = [_]u8{0} ** 16;
        tty.reset();
        logo.reset();
        vu.reset();

        zg.requestSongTune(MUSIC, 1);
        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });

        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.openBorders(.all);
        // The copper replaces openBorders()'s handler and flickers every line itself.
        copper.install(fb, &rasters.SLOTS, &rasters.tables, .{ .flicker = true });
        rasters.initTables();
        installPalette(fb);
        fb.clearFrameBuffer(A.C0);
        drawSpongeBob(blit.Dst.plane(fb));
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = dt; // frame-based: one loop a rendered frame
        frame += 1;
        ym = zigos.ym_regs;
        rasters.build(frame);
        tty.step();
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = dt;
        const d = blit.Dst.plane(&zigos.lfbs[PLANE]);
        vu.draw(d, &ym);
        logo.draw(d, frame);
        scroller.draw(d, frame);
        tty.render(d);
    }

    /// F1-F6: the six "Custodian" subtunes ($13D16). SPACE, Escape and Back leave.
    pub fn key(self: *Demo, cp: u32) void {
        _ = self;
        if (cp >= K_F1 and cp <= K_F6) {
            zg.requestSongTune(MUSIC, @intCast(1 + (cp - K_F1)));
        } else if (cp == K_ESC or cp == K_SPACE) {
            wants_quit = true;
        }
    }

    pub fn input(self: *Demo, dir: u8) void {
        _ = self;
        if (dir == DIR_BACK) wants_quit = true;
    }

    pub fn pollCart(self: *Demo) i32 {
        _ = self;
        return if (wants_quit) -1 else 0;
    }
};
