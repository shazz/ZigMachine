// --------------------------------------------------------------------------
// The best-effort parts, F3..F6 (parts.zig runs them): each on its own memory,
// its set-up's result as the asset, one VBL at a time, and captured through
// the display model of its interrupt chain.
//   f3  the ball-curve editor   rasters + the bottom border (raster.capture)
//   f4  TCB's letters and balls Timer B's magenta at line 183 (raster.capture)
//   f5  SYNC's giant scroller   full overscan, sync-scrolled (raster.captureFull)
//   f6  SYNC's vector balls     raster lines + the bottom border (f6_screen)
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");
const shifter = @import("shifter.zig");
const palette = @import("palette.zig");
const raster = @import("raster.zig");
const f3 = @import("f3.zig");
const f4 = @import("f4.zig");
const f5 = @import("f5.zig");
const f6 = @import("f6.zig");
const f6_screen = @import("f6_screen.zig");

pub const Id = enum { f3, f4, f5, f6 };

/// One frame's colour registers, line by line.
var lines: [f3.LINES][16]u16 = undefined;

/// The part's memory: `mem` from the part's base address on.
pub fn ram(id: Id, mem: []u8) st.Ram {
    const span: [2]u32 = switch (id) {
        .f3 => .{ f3.BASE, f3.TOP },
        .f4 => .{ f4.BASE, f4.TOP },
        .f5 => .{ f5.BASE, f5.TOP },
        .f6 => .{ f6.BASE, f6.TOP },
    };
    return .{ .base = span[0], .m = mem[0 .. span[1] - span[0]] };
}

/// A fresh start (the loader has just read it): black until its first VBL.
pub fn enter(id: Id, r: *const st.Ram) void {
    switch (id) {
        .f3 => f3.enter(),
        .f4 => {},
        .f5 => f5.enter(r),
        .f6 => f6.enter(r),
    }
    shifter.blank(st.color(0));
}

/// One VBL; `last` captures what the shifter shows.
pub fn vbl(id: Id, r: *const st.Ram, last: bool) void {
    switch (id) {
        .f3 => {
            const shown = f3.vbl(r);
            if (!last) return;
            f3.rasters(r, &lines);
            raster.capture(r, shown, &lines, f3.OPEN_FROM);
        },
        .f4 => {
            const shown = f4.vbl(r);
            if (!last) return;
            for (lines[0..200], 0..) |*l, y| l.* = f4.colours(r, y);
            raster.capture(r, shown, lines[0..200], 200);
        },
        .f5 => {
            const start = f5.vbl(r);
            if (last) raster.captureFull(r, start, f5.LINES, f5.FIRST_LINE, palette.at(r, f5.PALETTE), 0);
        },
        .f6 => {
            const shown = f6.vbl(r);
            if (last) f6_screen.capture(r, shown);
        },
    }
}

/// A key for the running part (only F3's panel takes any).
pub fn key(id: Id, cp: u32) void {
    if (id == .f3) f3.key(cp);
}
