// --------------------------------------------------------------------------
// KESTREL BOOT (WINDHOVER): a boot screen for KESTREL, the ZigMachine's FPGA console.
// Design and storyboard: prototypes/boot_screen/STUDY.md (concept 1). Original work.
//
// One gesture: a kestrel stoops into a dawn sky and stops dead, hovering, as the chord
// lands; the name lights under it; 4.8 s after power the picture has faded to black and
// stays black (a boot screen never loops: glass takes over from the black).
//
//   plane 0  RGB565 true colour, 400x280 (the Falcon's hi-colour): the sky, drawn once;
//            its fade in, the flash and the fade out are TC_FADE / TC_OFS (sky.zig)
//   plane 1  8-bit: the bird (CHISEL AFFINE during the stoop only, stoop.zig), the
//            highlight (a copper list), the wordmark (palette only) (marks.zig, word.zig)
//   sound    the YM2149 through zg.ymWrite, a register stream (jingle.zig)
//
// Integer-only per frame; frames are counted, dt is ignored (timeline.zig).
// apps/kestrel_boot_check.mjs proves it.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const tl = @import("kestrel_boot/timeline.zig");
const bird = @import("kestrel_boot/bird.zig");
const sky = @import("kestrel_boot/sky.zig");
const word = @import("kestrel_boot/word.zig");
const marks = @import("kestrel_boot/marks.zig");
const stoop = @import("kestrel_boot/stoop.zig");
const jingle = @import("kestrel_boot/jingle.zig");
const ZigOS = zg.ZigOS;

fn ymWrite(reg: u8, v: u8) bool {
    return zg.ymWrite(reg, v);
}

pub const Demo = struct {
    f: u32 = 0,
    ok: bool = false, // init found the RAM it needs (else the cart shows black and plays)
    marks: marks.Marks = undefined,
    stoop: stoop.Stoop = undefined,
    player: jingle.Player = .{},

    pub fn init(self: *Demo, os: *ZigOS) void {
        self.* = .{};
        const back = &os.lfbs[0];
        back.is_enabled = true;
        back.setTruecolorFade(31, .black);
        sky.paint(back.setTruecolorPlane(.full));
        const front = &os.lfbs[1];
        front.is_enabled = true;
        self.marks = marks.Marks.init(front);
        const tex = zg.mem.alloc(u8, bird.SIDE * bird.SIDE) orelse return;
        const spans = zg.mem.alloc(zg.chisel_v2.Span, 200) orelse return;
        bird.paint(tex);
        const m: u16 = bird.SIDE - 1;
        self.stoop = .{ .spans = spans, .tex = .{ .pixels = tex, .stride = bird.SIDE, .umask = m, .vmask = m, .wrap = false } };
        self.ok = true;
    }

    pub fn update(self: *Demo, os: *ZigOS, dt: f32) void {
        _ = os;
        _ = dt;
        self.player.tick(self.f, ymWrite);
    }

    pub fn render(self: *Demo, os: *ZigOS, dt: f32) void {
        _ = dt;
        const f = self.f;
        const back = &os.lfbs[0];
        back.setTruecolorFade(tl.fade(f), .black);
        const o = tl.flash(f);
        back.setTruecolorOffset(o, o, o);
        if (self.ok and f >= tl.STOOP and f <= tl.ARRIVE) self.stoop.draw(&os.lfbs[1], stoop.pose(f - tl.STOOP));
        // The letters go in after the stoop, whose clears sweep the plane; they are transparent until WORD.
        if (f == tl.ARRIVE + 1) word.paint(os, &os.lfbs[1]);
        self.marks.frame(&os.lfbs[1], f);
        if (self.f < tl.BLACK + 60) self.f += 1; // then hold: nothing changes any more
    }

    /// Frames since the cart started (the harness and, on the board, glass's hand-off read it).
    pub fn frameCount(self: *const Demo) u32 {
        return self.f;
    }
};
