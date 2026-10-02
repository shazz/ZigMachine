// --------------------------------------------------------------------------
// The menu's fullscreen through the shifter, onto the 400x280 overscan plane.
// MEASURED on Hatari's bordered capture (416x276, the normal window at x
// 48..367 / rows 29..228, so capture x = physical x + 8 and capture row r =
// physical line r + 11) by fitting it to the menu's screen in RAM
// (prototypes/naos_nitrowave_re/fit_geom.py, cmp_menu.py: 1,100 frames exact):
//   the top line      the 160 bytes before line 0: colour 0 (never written)
//   lines 0..256      230 bytes each from base+160, first pixel at capture x -4,
//                     open to capture x 411: physical (x, y) = line y-12, x+12
//   lines 257..       below the last line the VBL opens. What shows there is
//                     the same in every frame -- 15 star pixels -- and only
//                     those are drawn, as measured (bottom_rows.py).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const st = @import("st.zig");
const LINE = @import("menu_vbl.zig").LINE;

const PW: usize = zg.PHYSICAL_WIDTH;
const PH: usize = zg.PHYSICAL_HEIGHT;
const TOP: usize = 12; // physical row of line 0
const FIRST_PX: usize = 12; // line pixel at physical x 0
const LINES: usize = 257;

const Star = struct { y: u16, x: u16, c: u8 };
/// Capture rows 258..262 -> physical 269..273; capture x -> physical x - 8;
/// colours $112 / $223 / $445 are palette entries 1 / 2 / 4.
const stars = [_]Star{
    .{ .y = 269, .x = 57, .c = 1 },  .{ .y = 269, .x = 187, .c = 1 }, .{ .y = 269, .x = 272, .c = 1 },
    .{ .y = 269, .x = 358, .c = 1 }, .{ .y = 269, .x = 359, .c = 2 }, .{ .y = 270, .x = 131, .c = 1 },
    .{ .y = 270, .x = 183, .c = 1 }, .{ .y = 271, .x = 275, .c = 1 }, .{ .y = 271, .x = 341, .c = 4 },
    .{ .y = 271, .x = 343, .c = 4 }, .{ .y = 272, .x = 204, .c = 4 }, .{ .y = 272, .x = 206, .c = 4 },
    .{ .y = 272, .x = 256, .c = 4 }, .{ .y = 273, .x = 83, .c = 4 },  .{ .y = 273, .x = 109, .c = 4 },
};

/// The frame the shifter shows from `base` into the plane's 400x280 indices.
pub fn present(r: *const st.Ram, base: u32, px: []u8) void {
    @memset(px[0 .. TOP * PW], 0);
    for (0..LINES) |y| {
        const line = r.bytes(base + 160 + LINE * @as(u32, @intCast(y)), LINE);
        st.lineToChunky(line, FIRST_PX, px[(TOP + y) * PW ..][0..PW]);
    }
    @memset(px[(TOP + LINES) * PW .. PH * PW], 0);
    for (stars) |s| px[@as(usize, s.y) * PW + s.x] = s.c;
}

/// Palette entries 0..15 from the ST colour registers at `at`.
pub fn palette(r: *const st.Ram, at: u32, fb: *zg.LogicalFB) void {
    for (0..16) |i| fb.setPaletteEntry(@intCast(i), st.color(r.w(at + 2 * @as(u32, @intCast(i)))));
}
