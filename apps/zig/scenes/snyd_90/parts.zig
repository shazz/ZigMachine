// --------------------------------------------------------------------------
// The parts the loader runs from its table at $CA8, as this cart runs them:
// each on its own memory (st.zig), one VBL at a time, with what it shows
// captured for the shifter (shifter.zig) the way its VBL leaves it.
//   menu  part 0 -- menu.zig (entered fresh after every part, as on the ST)
//   f1    part 1 -- OMEGA's ball bending scroller (f1.zig)
//   f2    part 2 -- OMEGA's Liesen dist / HAQ scroll (f2.zig)
//   f3    part 3 -- the ball-curve editor (f3.zig), best effort
//   f5    part 5 -- SYNC's fullscreen giant scroller (f5.zig), best effort
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");
const shifter = @import("shifter.zig");
const palette = @import("palette.zig");
const assets = @import("assets.zig");
const menu = @import("menu.zig");
const f1 = @import("f1.zig");
const f2 = @import("f2.zig");
const f3 = @import("f3.zig");
const f5 = @import("f5.zig");
const raster = @import("raster.zig");

pub const Id = enum { menu, f1, f2, f3, f5 };

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
        // F5 plays a YM register STREAM ($1380C, 8 bytes a frame from $C006,
        // 3840 frames): it is Mad Max's Noisy Pillars (C64 conversion) -- the
        // archive's #1 writes the same tones, volumes, mixer and noise on all
        // 3840 frames at lag 0 (ymsearch.mjs found it by its registers).
        .f5 => .{ .file = "Noisy_Pillars.sndh", .n = 1 },
    };
}

pub fn set(id: Id) assets.Set {
    return switch (id) {
        .menu => .menu,
        .f1 => .f1,
        .f2 => .f2,
        .f3 => .f3,
        .f5 => .f5,
    };
}

/// A key for the running part (only F3's panel takes any): the host's
/// codepoint, or an arrow as 0xF000 + direction (0 up, 1 down, 2 left, 3 right).
pub fn key(cp: u32) void {
    f3.key(cp);
}

/// A raster part's colour registers, line by line (one frame's).
var lines: [f3.LINES][16]u16 = undefined;

pub const Running = struct {
    id: Id,
    r: st.Ram,
    pal: [16]u16, // the colour registers, for a part that writes them

    /// `mem` holds the part as its asset left it: start it, capture its
    /// first frame.
    pub fn enter(id: Id, mem: []u8) Running {
        switch (id) {
            .menu => {
                const r = st.Ram{ .base = menu.BASE, .m = mem[0 .. menu.TOP - menu.BASE] };
                menu.init(&r);
                const self = Running{ .id = id, .r = r, .pal = palette.at(&r, menu.PALETTE) };
                shifter.captureScreen(&r, menu.iteration(&r), self.pal);
                return self;
            },
            .f1 => {
                const r = st.Ram{ .base = f1.BASE, .m = mem[0 .. f1.TOP - f1.BASE] };
                shifter.captureScreen(&r, f1.SCREEN, f1.PALETTE); // the ball, no text yet
                return .{ .id = id, .r = r, .pal = f1.PALETTE };
            },
            .f2 => {
                const r = st.Ram{ .base = f2.BASE, .m = mem[0 .. f2.TOP - f2.BASE] };
                const self = Running{ .id = id, .r = r, .pal = palette.at(&r, f2.PALETTE) };
                shifter.blank(st.color(0)); // its set-up cleared both screens
                return self;
            },
            .f3 => {
                f3.enter();
                const r = st.Ram{ .base = f3.BASE, .m = mem[0 .. f3.TOP - f3.BASE] };
                shifter.blank(st.color(0));
                return .{ .id = id, .r = r, .pal = palette.at(&r, f3.PALETTE) };
            },
            .f5 => {
                const r = st.Ram{ .base = f5.BASE, .m = mem[0 .. f5.TOP - f5.BASE] };
                f5.enter(&r);
                shifter.blank(st.color(0));
                return .{ .id = id, .r = r, .pal = palette.at(&r, f5.PALETTE) };
            },
        }
    }

    /// One VBL; `last` captures what the shifter shows.
    pub fn vbl(self: *Running, last: bool) void {
        switch (self.id) {
            .menu => {
                const shown = menu.iteration(&self.r);
                if (last) shifter.captureScreen(&self.r, shown, self.pal);
            },
            .f1 => { // one screen, redrawn in place ahead of the beam
                f1.frame(&self.r);
                if (last) shifter.captureScreen(&self.r, f1.SCREEN, self.pal);
            },
            .f2 => {
                const shown = f2.top(&self.r, &self.pal);
                if (last) shifter.captureScreen(&self.r, shown, self.pal);
                f2.bottom(&self.r);
            },
            .f3 => {
                const shown = f3.vbl(&self.r);
                if (!last) return;
                f3.rasters(&self.r, &lines);
                raster.capture(&self.r, shown, &lines, f3.OPEN_FROM);
            },
            .f5 => {
                const start = f5.vbl(&self.r);
                if (!last) return;
                const pal = palette.at(&self.r, f5.PALETTE);
                raster.captureFull(&self.r, start, f5.LINES, f5.FIRST_LINE, pal, 0);
            },
        }
    }
};
