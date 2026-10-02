// --------------------------------------------------------------------------
// The parts the loader runs from its table at $CA8, as this cart runs them:
// each on its own memory (st.zig), one VBL at a time, with what it shows
// captured for the shifter (shifter.zig) the way its VBL leaves it.
//   menu  part 0 -- menu.zig (entered fresh after every part, as on the ST)
//   f2    part 2 -- OMEGA's Liesen dist / HAQ scroll (f2.zig)
// F1, F3..F6 (parts 1, 3..6) are not ported: the menu ignores those keys.
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");
const shifter = @import("shifter.zig");
const palette = @import("palette.zig");
const assets = @import("assets.zig");
const menu = @import("menu.zig");
const f2 = @import("f2.zig");

pub const Id = enum { menu, f2 };

pub const Tune = struct { file: []const u8, n: u8 };

pub fn tune(id: Id) Tune {
    return switch (id) {
        // The menu's COSO replay + module ($79C4), subtune 1 (4 is the intro's).
        .menu => .{ .file = "snyd90.sndh", .n = 1 },
        // F2's TFMX replay + module ($8836..$AF16), init d0 = 0.
        .f2 => .{ .file = "snyd90_f2.sndh", .n = 1 },
    };
}

pub fn set(id: Id) assets.Set {
    return switch (id) {
        .menu => .menu,
        .f2 => .f2,
    };
}

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
            .f2 => {
                const r = st.Ram{ .base = f2.BASE, .m = mem[0 .. f2.TOP - f2.BASE] };
                const self = Running{ .id = id, .r = r, .pal = palette.at(&r, f2.PALETTE) };
                shifter.blank(st.color(0)); // its set-up cleared both screens
                return self;
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
            .f2 => {
                const shown = f2.top(&self.r, &self.pal);
                if (last) shifter.captureScreen(&self.r, shown, self.pal);
                f2.bottom(&self.r);
            },
        }
    }
};
