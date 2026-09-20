// --------------------------------------------------------------------------
// The "V" title — the full-screen picture the demo opens on, before the intro.
//
// It is the demo's own content, not a packer intro, and it is a separate part
// of the program at $804.  Read out of the code, not invented:
//   $894   copies 32000 bytes from $44fc into the back buffer, once.
//   $842's VBL crossfades the live palette toward the picture's own palette at
//          $44dc using the SAME fader the intro uses ($ab86), with d6 = 1 (one
//          level per channel per frame) and d7 = $f, i.e. 16 words.
//   $80a   fills $ff8240 with $0777 first, so the picture resolves OUT OF white.
//   $842   refills that target with white at frame $fa (250) — so it flashes
//          back out — and at $12c (300) clears the screen and hands over.
//
// STE has 16 levels per channel, so each fade settles in ~15 frames and then
// simply holds; the 250/300 marks are the holds, not the ramps.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;

const A = @import("assets.zig");
const pal = @import("palette.zig");

const WHITE: u16 = 0x0777; // $80a's fill, and the target again past HOLD
const COLOURS: usize = 16; // d7 = $f
pub const HOLD: u16 = 250; // $fa: the target is refilled white here
pub const END: u16 = 300; // $12c: clear and start the intro

pub const Title = struct {
    live: [COLOURS]u16,
    t: u16,

    pub fn init(self: *Title, fb: *LogicalFB) void {
        self.t = 0;
        for (&self.live) |*c| c.* = WHITE;
        for (0..A.VTITLE_H) |y| {
            const src = A.vtitle[y * zg.WIDTH ..][0..zg.WIDTH];
            @memcpy(fb.fb[y * fb.stride ..][0..zg.WIDTH], src);
        }
        self.publish(fb);
    }

    pub fn step(self: *Title) void {
        const out = self.t >= HOLD; // past $fa the target is white again
        for (&self.live, 0..) |*c, i| {
            c.* = pal.stepColour(c.*, if (out) WHITE else A.be(A.vtitle_pal_b, i));
        }
        self.t += 1;
    }

    pub fn done(self: *const Title) bool {
        return self.t >= END;
    }

    pub fn publish(self: *const Title, fb: *LogicalFB) void {
        for (self.live, 0..) |c, i| fb.palette[i] = pal.rgba(c);
    }
};
