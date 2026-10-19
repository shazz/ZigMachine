// --------------------------------------------------------------------------
// F1 through the shifter: a 320-pixel screen (160-byte lines) whose bottom
// border the Timer B handler opens, so 247 lines show. Timer B ($E08) fires
// at the end of every line and loads colours 0 and 1 from the table at
// $47524; at its 60th interrupt it loads the logo's colours 3, 5..13. Colour
// 0 is the side borders' colour too, so each bar runs the full width.
//
// A REAL raster: each physical row's palette is the colour registers as Timer
// B leaves them for that line, loaded by the plane's HBL before the row shows
// (which also opens the borders). APPROXIMATED: the original's colour change
// lands where the 68000 takes the interrupt -- up to ~40 pixels into the line
// when the VBL's long instructions delay it, and at x 177 / 9 on lines
// 200/201 after the bottom-border code. Here every change is at its nominal
// line start (prototypes/naos_nitrowave_re/ric_show.py, the same model: = the
// Hatari captures but for those late changes).
// Geometry: capture (x, row) = physical (x + 8, row - 11); line 0 is capture
// row 29, pixel 0 capture x 48 (ric_show.py) -> physical row 40, x 40.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const st = @import("st.zig");
const scroll = @import("ric_scroll.zig");
const init = @import("ric_init.zig");
const font = @import("ric_font.zig");

const PW: usize = zg.PHYSICAL_WIDTH;
const PH: usize = zg.PHYSICAL_HEIGHT;
const TOP: usize = 40; // physical row of line 0
const LEFT: usize = 40; // physical x of pixel 0
pub const LINES: u16 = 247; // 200 + the opened bottom border
const LOGO_AT: u16 = 60; // the Timer B count reaches $8A
const LOGO_COLOURS = [6]u4{ 3, 5, 7, 9, 11, 13 };

/// The colour registers, a state carried from line to line and frame to frame.
pub const Regs = struct {
    p: [16]u16,

    /// $D76..$D82: the part's palette, colour 1 cleared.
    pub fn start(r: *const st.Ram) Regs {
        var g: Regs = undefined;
        for (&g.p, 0..) |*c, i| c.* = r.w(init.PALETTE + 2 * @as(u32, @intCast(i)));
        g.p[1] = 0;
        return g;
    }

    /// $101A..$104C: colours 3, 5..13 from the palette, colour 1 from the
    /// scroller's colour list as it stands before the VBL moves it on.
    pub fn vbl(self: *Regs, r: *const st.Ram) void {
        for (LOGO_COLOURS, 0..) |c, k| self.p[c] = r.w(init.PALETTE + 6 + 4 * @as(u32, @intCast(k)));
        self.p[1] = r.w(r.l(r.l(scroll.SCROLL_LIST)));
    }

    /// Timer B's k-th interrupt (k = 1 at the end of line 0).
    pub fn hbl(self: *Regs, r: *const st.Ram, k: u16) void {
        const at = scroll.TABLE + 4 * (@as(u32, k) - 1);
        self.p[0] = r.w(at);
        self.p[1] = r.w(at + 2);
        if (k != LOGO_AT) return;
        for (LOGO_COLOURS, 0..) |c, j| self.p[c] = r.w(init.LOGO_PAL + 6 + 4 * @as(u32, @intCast(j)));
    }

    /// A whole frame's interrupts: the state the next frame starts from.
    pub fn frame(self: *Regs, r: *const st.Ram) void {
        for (1..LINES) |k| self.hbl(r, @intCast(k));
    }
};

const Row = [16]u32;
var rows: []Row = &.{};
/// Which of a row's colours differ from the row above's (all, on row 0): the HBL loads those only.
var masks: []u16 = &.{};
/// The planar line each row was last converted from, so a line the VBL did not touch is not
/// converted (and its borders not repainted) again: the plane keeps its pixels between frames.
/// `reset()` (a new part) and the title forget them and repaint everything.
var shadow: []u8 = &.{};
var shadow_ok = false;

pub fn reset() void {
    shadow_ok = false;
}

fn fill(dst: *Row, p: *const [16]u16, above: ?*const Row) u16 {
    var m: u16 = if (above == null) 0xFFFF else 0;
    for (dst, p, 0..) |*c, w, i| {
        const v = st.rgba(w);
        if (c.* != v) c.* = v; // a store is a bus write; the row mostly holds the colours already
        if (above) |ab| if (ab[i] != v) {
            m |= @as(u16, 1) << @intCast(i);
        };
    }
    return m;
}

fn rowsReady() void {
    if (rows.len == 0) {
        rows = zg.mem.mustAlloc(Row, PH);
        masks = zg.mem.mustAlloc(u16, PH);
        shadow = zg.mem.mustAlloc(u8, (PH - TOP) * 160);
    }
}

/// The frame shown from `base` with the registers as the VBL left them.
pub fn present(r: *const st.Ram, base: u32, start: Regs, px: []u8) void {
    rowsReady();
    var g = start;
    if (!shadow_ok) @memset(px[0 .. TOP * PW], 0);
    for (0..TOP) |y| masks[y] = fill(&rows[y], &g.p, if (y > 0) &rows[y - 1] else null);
    for (0..PH - TOP) |li| {
        const line: u16 = @intCast(li);
        if (line >= 1) g.hbl(r, line);
        const y = TOP + li;
        const planar = r.bytes(base + 160 * @as(u32, line), 160);
        const kept = shadow[li * 160 ..][0..160];
        if (!shadow_ok or !st.same(planar, kept)) {
            st.copyBytes(kept, planar);
            screenRow(planar, px[y * PW ..][0..PW], !shadow_ok);
        }
        masks[y] = fill(&rows[y], &g.p, &rows[y - 1]);
    }
    shadow_ok = true;
}

/// One line: colour 0 in the borders (`borders`: they need painting), the 320 pixels between.
fn screenRow(line: []const u8, out: []u8, borders: bool) void {
    if (borders) {
        @memset(out[0..LEFT], 0);
        @memset(out[LEFT + 320 ..], 0);
    }
    st.lineToChunky(line, 0, out[LEFT..][0..320]);
}

/// The title: a plain 200-line screen (no Timer B yet) in its own palette.
pub fn presentTitle(r: *const st.Ram, px: []u8) void {
    rowsReady();
    var p: [16]u16 = undefined;
    for (&p, 0..) |*c, i| c.* = r.w(font.TITLE + 2 + 2 * @as(u32, @intCast(i)));
    for (0..PH) |y| {
        masks[y] = fill(&rows[y], &p, if (y > 0) &rows[y - 1] else null);
        const out = px[y * PW ..][0..PW];
        if (y < TOP or y >= TOP + 200) {
            @memset(out, 0);
        } else screenRow(r.bytes(font.TITLE_SCREEN + 160 * @as(u32, @intCast(y - TOP)), 160), out, true);
    }
    shadow_ok = false;
}

/// The plane's HBL: open the borders, load this row's colour registers.
pub fn hbl(fb: *zg.LogicalFB, _: *zg.ZigOS, line: u16, _: u16) void {
    fb.flickerBorder();
    if (line >= rows.len) return;
    var m = masks[line];
    while (m != 0) : (m &= m - 1) {
        const i = @ctz(m);
        const slot = &fb.palette[i];
        if (slot.* != rows[line][i]) slot.* = rows[line][i]; // a raster coder never rewrites a register that holds the colour
    }
}
