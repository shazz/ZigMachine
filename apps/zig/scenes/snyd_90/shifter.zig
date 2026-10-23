// --------------------------------------------------------------------------
// What the ST's shifter shows, on one overscan plane (400x280): a part's
// screen as palette indices (rows.zig), and the colour registers as they
// stand on each physical line -- up to 16 for an ST line, 48 for the intro's
// Spectrum 512 lines, which rewrite all 48 while the beam runs. The plane's
// HBL loads a line's entries before the line is drawn; the global HBL paints
// the closed borders with colour 0, as on an ST, where the border IS colour 0.
//
// The machine paints the borders BEFORE the cart runs, so a frame is captured
// one host frame ahead (as cart 76 does): a capture at the end of a render
// fills the *_next state, present() at the start of the next makes it
// current. Plane and borders then show the same iteration.
//
// KESTREL: every store is a blocking bus write, so a capture stores only what
// differs from the last one (pixels: rows.zig; registers: setRegs), and
// present() moves only the lines that changed.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const st = @import("../swedish_newyear/st.zig");
const rows = @import("rows.zig");

pub const PW: usize = rows.PW; // 400
pub const PH: usize = rows.PH; // 280
pub const OX: usize = zg.HORIZONTAL_BORDERS_WIDTH; // the 320x200 window at (40, 40)
pub const OY: usize = zg.VERTICAL_BORDERS_HEIGHT;
/// Most colour registers one line can need: the intro's three sets of 16.
pub const MAXC = 48;

pub const Line = [MAXC]u32;

var now: *[PH]Line = undefined; // the colours the plane shows this frame
var next: *[PH]Line = undefined;
var used_now: [PH]u8 = undefined;
var used_next: [PH]u8 = undefined;
var c0_next: [PH]u32 = undefined; // closed borders, read by the global HBL
var open_now: [PH]bool = undefined; // lines whose borders a part opened
var open_next: [PH]bool = undefined;
var line_dirty: [PH]bool = undefined; // a line's registers or border changed since present()
/// Something was captured since the last present(): when nothing was (a part
/// that stands still, the intro's picture), the plane already shows it all.
var captured: bool = true;

/// Once per cart load: the buffers (zg.mem), the plane and both HBLs.
pub fn init(zigos: *zg.ZigOS) void {
    rows.init();
    now = zg.mem.mustAlloc(Line, PH)[0..PH];
    next = zg.mem.mustAlloc(Line, PH)[0..PH];
    captured = true;
    @memset(&used_now, 0);
    @memset(&used_next, 0);
    @memset(&c0_next, st.color(0));
    @memset(&open_now, false);
    @memset(&open_next, false);
    @memset(&line_dirty, false);
    const fb = &zigos.lfbs[0];
    fb.setOverscanBuffer();
    fb.is_enabled = true;
    fb.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, planeHbl);
    zigos.setHBLHandler(borderHbl);
}

/// A low-res ST screen at `screen` in `r`, every line under the colour
/// registers `pal` (no rasters); the borders show its colour 0.
pub fn captureScreen(r: *const st.Ram, screen: u32, pal: [16]u16) void {
    const regs = rgba(pal);
    for (0..PH) |py| {
        if (py >= OY and py < OY + 200) {
            window(r, py, screen + @as(u32, @intCast(py - OY)) * st.LINE);
        } else rows.blank(py);
        setRegs(py, &regs);
        setOpen(py, false);
    }
}

/// Physical row `py` shows the 320-pixel ST line at `addr` in the window.
pub fn window(r: *const st.Ram, py: usize, addr: u32) void {
    captured = true;
    rows.planar(r, py, addr, OX, 20);
}

/// Physical row `py` shows the 26 groups of a full-overscan line from `addr`,
/// its first pixel 12 left of the plane (the open left border reaches 52
/// pixels past the window, the plane 40).
pub fn full(r: *const st.Ram, py: usize, addr: u32) void {
    captured = true;
    rows.planar(r, py, addr, -12, 26);
}

/// Physical row `py` all colour 0.
pub fn blankRow(py: usize) void {
    captured = true;
    rows.blank(py);
}

/// Physical row `py` as palette indices the caller computes (zeroed when it
/// was not such a row before).
pub fn customRow(py: usize) *[PW]u8 {
    captured = true;
    return rows.customRow(py);
}

/// Physical row `py`'s colour registers (at most MAXC); entry 0 is also
/// what its closed borders show. Stores only the entries that change.
pub fn setRegs(py: usize, regs: []const u32) void {
    lineRegs(py, regs);
    if (c0_next[py] != regs[0]) c0_next[py] = regs[0];
}

fn lineRegs(py: usize, regs: []const u32) void {
    captured = true;
    var changed = used_next[py] != regs.len;
    for (next[py][0..regs.len], regs) |*c, v| if (c.* != v) {
        c.* = v;
        changed = true;
    };
    if (changed) {
        used_next[py] = @intCast(regs.len);
        line_dirty[py] = true;
    }
}

/// Whether physical row `py`'s borders are open: the plane's HBL then
/// flickers the line (zg's res-flicker, the ST's 50/60 Hz or res switch).
pub fn setOpen(py: usize, open: bool) void {
    captured = true;
    if (open_next[py] == open) return;
    open_next[py] = open;
    line_dirty[py] = true;
}

/// The 16 colour registers as the plane stores them.
pub fn rgba(pal: [16]u16) [16]u32 {
    var regs: [16]u32 = undefined;
    for (&regs, pal) |*c, w| c.* = st.color(w);
    return regs;
}

/// The window row `y` (0..199) as palette indices, to fill directly.
pub fn row(y: usize) *[320]u8 {
    return customRow(OY + y)[OX..][0..320];
}

/// Line `y` of the window: its colour registers as RGBA (at most MAXC). Call
/// blank() first: it sets the lines outside the window.
pub fn setLine(y: usize, regs: []const u32) void {
    lineRegs(OY + y, regs); // its border keeps blank()'s colour 0
}

/// Clear the whole plane to index 0 and every line to one colour 0.
pub fn blank(border: u32) void {
    for (0..PH) |py| {
        blankRow(py);
        setRegs(py, &.{border});
        setOpen(py, false);
    }
}

/// Start of a host frame: the captured frame becomes what the machine shows.
pub fn present(fb: *zg.LogicalFB) void {
    if (!captured) return;
    captured = false;
    rows.present(fb.fb);
    for (0..PH) |py| {
        if (!line_dirty[py]) continue;
        line_dirty[py] = false;
        const n = used_next[py];
        for (now[py][0..n], next[py][0..n]) |*c, v| if (c.* != v) {
            c.* = v;
        };
        used_now[py] = n;
        open_now[py] = open_next[py];
    }
}

fn planeHbl(fb: *zg.LogicalFB, _: *zg.ZigOS, line: u16, _: u16) void {
    if (line >= PH) return;
    if (open_now[line]) fb.flickerBorder();
    // Only the entries that change: a raster coder never rewrites a register
    // that already holds the colour (a load is free on the board, a store is not).
    for (now[line][0..used_now[line]], 0..) |c, i| {
        if (fb.palette[i] != c) fb.palette[i] = c;
    }
}

fn borderHbl(zigos: *zg.ZigOS, line: u16) void {
    zigos.setBackgroundColor(zg.Color.fromRGBA(c0_next[@min(line, PH - 1)]));
}
