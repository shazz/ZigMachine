// --------------------------------------------------------------------------
// The parts the loader runs from its table at $CA8, as this cart runs them:
// each on its own memory (st.zig), one VBL at a time, with what it shows
// captured for the shifter (shifter.zig) the way its VBL leaves it.
//   menu  part 0 -- menu.zig (entered fresh after every part, as on the ST)
//   f1    part 1 -- OMEGA's ball bending scroller (f1.zig)
//   f2    part 2 -- OMEGA's Liesen dist / HAQ scroll (f2.zig)
//   f3..f6 parts 3..6 -- best effort (later.zig): the ball-curve editor,
//                        TCB's letters and balls, SYNC's fullscreen scroller,
//                        SYNC's vector balls
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");
const shifter = @import("shifter.zig");
const palette = @import("palette.zig");
const assets = @import("assets.zig");
const menu = @import("menu.zig");
const f1 = @import("f1.zig");
const f2 = @import("f2.zig");
const later = @import("later.zig");

pub const Id = enum { menu, f1, f2, f3, f4, f5, f6 };

pub const Tune = struct { file: []const u8, n: u8 };

pub fn tune(id: Id) Tune {
    return switch (id) {
        // The menu's COSO replay + module ($79C4), subtune 1 (4 is the intro's).
        .menu => .{ .file = "snyd90.sndh", .n = 1 },
        // F1's replay ($3B24..) is Jas C. Brooke's Overlander, init d0 = 0: the
        // archive's Overlander.sndh #1 writes the same YM registers on every
        // frame (1500 of 1500, lag 0, against the original on the oracle).
        .f1 => .{ .file = "Overlander.sndh", .n = 1 },
        // F2's TFMX replay + module ($8836..$AF16), init d0 = 0.
        .f2 => .{ .file = "snyd90_f2.sndh", .n = 1 },
        // F3's Whittaker replay + Platoon ($1CA66..$1EB28), init d0 = 4: the
        // SNDH passes the subtune as d0 (YM equal to the oracle's, 1500 frames).
        .f3 => .{ .file = "snyd90_f3.sndh", .n = 4 },
        // F4's Mad Max replay ($17FC0, init d0 = 2) plays Rollout: the archive's
        // #2 writes the oracle's registers on 1498 of 1499 frames (the first
        // differs: the part's set-up already played a few).
        .f4 => .{ .file = "rollout.sndh", .n = 2 },
        // F5 plays a YM register STREAM ($1380C, 8 bytes a frame from $C006,
        // 3840 frames): it is Mad Max's Noisy Pillars (C64 conversion) -- the
        // archive's #1 writes the same tones, volumes, mixer and noise on all
        // 3840 frames at lag 0 (ymsearch.mjs found it by its registers).
        .f5 => .{ .file = "Noisy_Pillars.sndh", .n = 1 },
        // F6's sample replay of the module Wasteland ($E50E.., Timer C at
        // 7.4 kHz), relocated into an SNDH (mk_f6_sndh.py).
        .f6 => .{ .file = "snyd90_f6.sndh", .n = 1 },
    };
}

pub fn set(id: Id) assets.Set {
    return switch (id) {
        .menu => .menu,
        .f1 => .f1,
        .f2 => .f2,
        .f3 => .f3,
        .f4 => .f4,
        .f5 => .f5,
        .f6 => .f6,
    };
}

fn laterId(id: Id) ?later.Id {
    return switch (id) {
        .f3 => .f3,
        .f4 => .f4,
        .f5 => .f5,
        .f6 => .f6,
        else => null,
    };
}

pub const Running = struct {
    id: Id,
    r: st.Ram,
    pal: [16]u16, // the colour registers, for a part that writes them

    /// `mem` holds the part as its asset left it: start it, capture its
    /// first frame.
    pub fn enter(id: Id, mem: []u8) Running {
        if (laterId(id)) |l| {
            const r = later.ram(l, mem);
            later.enter(l, &r);
            return .{ .id = id, .r = r, .pal = [_]u16{0} ** 16 };
        }
        return switch (id) {
            .menu => enterMenu(mem),
            .f1 => {
                const r = st.Ram{ .base = f1.BASE, .m = mem[0 .. f1.TOP - f1.BASE] };
                shifter.captureScreen(&r, f1.SCREEN, f1.PALETTE); // the ball, no text yet
                return .{ .id = id, .r = r, .pal = f1.PALETTE };
            },
            else => {
                const r = st.Ram{ .base = f2.BASE, .m = mem[0 .. f2.TOP - f2.BASE] };
                shifter.blank(st.color(0)); // its set-up cleared both screens
                return .{ .id = id, .r = r, .pal = palette.at(&r, f2.PALETTE) };
            },
        };
    }

    fn enterMenu(mem: []u8) Running {
        const r = st.Ram{ .base = menu.BASE, .m = mem[0 .. menu.TOP - menu.BASE] };
        menu.init(&r);
        const self = Running{ .id = .menu, .r = r, .pal = palette.at(&r, menu.PALETTE) };
        shifter.captureScreen(&r, menu.iteration(&r), self.pal);
        return self;
    }

    /// One VBL; `last` captures what the shifter shows.
    pub fn vbl(self: *Running, last: bool) void {
        if (laterId(self.id)) |l| return later.vbl(l, &self.r, last);
        switch (self.id) {
            .menu => {
                const shown = menu.iteration(&self.r);
                if (last) shifter.captureScreen(&self.r, shown, self.pal);
            },
            .f1 => { // one screen, redrawn in place ahead of the beam
                f1.frame(&self.r);
                if (last) shifter.captureScreen(&self.r, f1.SCREEN, self.pal);
            },
            else => {
                const shown = f2.top(&self.r, &self.pal);
                if (last) shifter.captureScreen(&self.r, shown, self.pal);
                f2.bottom(&self.r);
            },
        }
    }

    /// A key for the running part (only F3's panel takes any): the host's
    /// codepoint, or an arrow as 0xF000 + direction (0 up, 1 down, 2 left, 3 right).
    pub fn key(self: *const Running, cp: u32) void {
        if (laterId(self.id)) |l| later.key(l, cp);
    }
};
