// --------------------------------------------------------------------------
// OMEGA (F3 on the menu), from the disk: the loader reads tracks 38..44 to
// $8000 and jumps in (prototypes/snyd_re/NOTES_omega.md). One screen, all of
// its work in the VBL (omega_vbl.zig), on the part's own memory (st.zig) at the
// original's 50 Hz, one VBL every 20 ms of host time. Every F3 is a fresh start.
//
//   * the picture (Red of OMEGA) fills the whole 320-pixel width from line 0,
//     170 lines; the ATARI logo twists and bounces in it; the scroller runs on
//     lines 172..187 in the picture's colours 1..3.
//   * the BOTTOM BORDER is opened (Timer B at the end of line 199, $81EA: a
//     60 Hz / 50 Hz switch) and the palette $C94E loaded for the lines below:
//     the LED panel on lines 201..224 of the same screen memory, where plane 3
//     lights the six meters. The picture's palette $DD5E is set by the VBL.
//     Colour 0 is black in both: no rasters.
//   * Space (release, $B9 on $FFFC02) leaves: MFP and VBL restored, colour 0 =
//     $777, sound off -- and the loader reloads the menu.
//
// The CODEF remake drew the picture scaled to about 0.83 (266x124 from line
// 21), the meters inside the screen with a decay the original has not, and a
// 31-frame spinning ATARI sprite in place of the twisting logo.
// --------------------------------------------------------------------------
const st = @import("st.zig");
const show = @import("st_show.zig");
const fr = @import("frame.zig");
const init_part = @import("omega_init.zig").init;
const vbl = @import("omega_vbl.zig").vbl;
const assets = @import("assets.zig");
const ram = @import("ram.zig");

pub const BASE: u32 = 0x8000; // where the loader puts the OMEGA part
pub const TOP: u32 = 0x80000;
pub const SCREEN: u32 = 0x70000;
pub const FRAMES: u32 = 0x40000; // the logo's 32 frames
pub const LOGO_FRAMES = 32;
pub const LOGO_LINES = 89;
pub const LOGO_BYTES = 56; // a built line: 7 groups, 112 pixels
pub const FRAME_BYTES: u32 = 0x1378; // mulu #$1378 at $8772
comptime {
    if (LOGO_LINES * LOGO_BYTES != FRAME_BYTES) @compileError("a logo frame is 89 lines of 56 bytes");
}
const PALETTE: u32 = 0xDD5E; // lines 0..199 (the VBL)
const LOWER_PALETTE: u32 = 0xC94E; // from line 200 (Timer B)

pub const Omega = struct {
    r: st.Ram,
    acc: f32,

    /// The part's tracks are in the part buffer (assets.load(.omega)); the
    /// first VBL runs at once, with the voices' levels as they stand.
    pub fn enter(self: *Omega, levels: [3]u8) void {
        const part = ram.buf.part[0..assets.OMEGA_RAM];
        @memset(part[assets.OMEGA_IMAGE..], 0);
        self.r = .{ .base = BASE, .m = part };
        init_part(&self.r);
        self.acc = 0;
        vbl(&self.r, levels);
        self.capture();
    }

    /// One host frame: show what was captured, run the VBLs due, capture.
    pub fn frame(self: *Omega, fb: []u8, dt: f32, levels: [3]u8) void {
        fr.setBorders(.bottom);
        show.presentOverscan(fb);
        self.acc += dt;
        while (self.acc >= st.VBL_MS) : (self.acc -= st.VBL_MS) vbl(&self.r, levels);
        self.capture();
    }

    fn capture(self: *const Omega) void {
        var upper: [16]u16 = undefined;
        var lower: [16]u16 = undefined;
        for (&upper, &lower, 0..) |*u, *l, i| {
            const off = 2 * @as(u32, @intCast(i));
            u.* = self.r.w(PALETTE + off);
            l.* = self.r.w(LOWER_PALETTE + off);
        }
        var rows: show.Rows = [_]?show.Row{null} ** fr.PH;
        var pals: show.LinePalettes = undefined;
        const oy: usize = @intCast(fr.OY);
        const x0: i32 = fr.OX;
        for (&pals, &rows, 0..) |*pal, *row, py| {
            pal.* = if (py >= oy + show.LINES) lower else upper;
            if (py < oy) continue;
            // 200 lines and the 40 of the opened bottom border the machine shows
            const y: u32 = @intCast(py - oy);
            row.* = .{ .addr = SCREEN + y * st.LINE, .x0 = x0, .lo = @intCast(x0), .hi = @intCast(x0 + 320) };
        }
        show.captureLines(&self.r, &rows, &pals);
    }
};
