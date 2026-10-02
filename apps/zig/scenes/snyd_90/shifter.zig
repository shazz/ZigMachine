// --------------------------------------------------------------------------
// What the ST's shifter shows, on one overscan plane (400x280): a part's
// screen as palette indices, and the colour registers as they stand on each
// physical line -- up to 16 for an ST line, 48 for the intro's Spectrum 512
// lines, which rewrite all 48 while the beam runs. The plane's HBL loads a
// line's entries before the line is drawn; the global HBL paints the closed
// borders with colour 0, as on an ST, where the border IS colour 0.
//
// The machine paints the borders BEFORE the cart runs, so a frame is captured
// one host frame ahead (as cart 76 does): capture*() at the end of a render
// fills the *_next tables, present() at the start of the next makes them
// current. Plane and borders then show the same iteration.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const st = @import("../swedish_newyear/st.zig");

pub const PW: usize = zg.PHYSICAL_WIDTH; // 400
pub const PH: usize = zg.PHYSICAL_HEIGHT; // 280
pub const OX: usize = zg.HORIZONTAL_BORDERS_WIDTH; // the 320x200 window at (40, 40)
pub const OY: usize = zg.VERTICAL_BORDERS_HEIGHT;
/// Most colour registers one line can need: the intro's three sets of 16.
pub const MAXC = 48;

pub const Line = [MAXC]u32;

const Buffers = struct {
    chunky: *[PH][PW]u8, // the next frame, palette indices
    now: *[PH]Line, // the colours the plane shows this frame
    next: *[PH]Line,
};

var buf: Buffers = undefined;
var used_now: [PH]u8 = undefined;
var used_next: [PH]u8 = undefined;
var c0_next: [PH]u32 = undefined; // closed borders, read by the global HBL

/// Once per cart load: the buffers (zg.mem), the plane and both HBLs.
pub fn init(zigos: *zg.ZigOS) void {
    buf = .{
        .chunky = zg.mem.mustAlloc([PW]u8, PH)[0..PH],
        .now = zg.mem.mustAlloc(Line, PH)[0..PH],
        .next = zg.mem.mustAlloc(Line, PH)[0..PH],
    };
    @memset(&used_now, 0);
    @memset(&used_next, 0);
    @memset(&c0_next, st.color(0));
    const fb = &zigos.lfbs[0];
    fb.setOverscanBuffer();
    fb.is_enabled = true;
    fb.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, planeHbl);
    zigos.setHBLHandler(borderHbl);
}

/// A low-res ST screen at `screen` in `r`, every line under the colour
/// registers `pal` (no rasters); the borders show its colour 0.
pub fn captureScreen(r: *const st.Ram, screen: u32, pal: [16]u16) void {
    var regs: [16]u32 = undefined;
    for (&regs, pal) |*c, w| c.* = st.color(w);
    for (0..PH) |py| {
        const out = &buf.chunky[py];
        @memset(out, 0);
        if (py >= OY and py < OY + 200) {
            const y: u32 = @intCast(py - OY);
            st.lineToChunky(r.bytes(screen + y * st.LINE, st.LINE), out[OX..][0..320]);
        }
        @memcpy(buf.next[py][0..16], &regs);
        used_next[py] = 16;
        c0_next[py] = regs[0];
    }
}

/// The window row `y` (0..199) as palette indices, to fill directly.
pub fn row(y: usize) *[320]u8 {
    return buf.chunky[OY + y][OX..][0..320];
}

/// Line `y` of the window: its colour registers as RGBA (at most MAXC). Call
/// blank() first: it sets the lines outside the window.
pub fn setLine(y: usize, regs: []const u32) void {
    @memcpy(buf.next[OY + y][0..regs.len], regs);
    used_next[OY + y] = @intCast(regs.len);
}

/// Clear the whole plane to index 0 and every line to one colour 0.
pub fn blank(border: u32) void {
    for (buf.chunky) |*r| @memset(r, 0);
    for (0..PH) |py| {
        buf.next[py][0] = border;
        used_next[py] = 1;
        c0_next[py] = border;
    }
}

/// Start of a host frame: the captured frame becomes what the machine shows.
pub fn present(fb: *zg.LogicalFB) void {
    for (buf.chunky, 0..) |*r, py| @memcpy(fb.fb[py * PW ..][0..PW], r);
    buf.now.* = buf.next.*;
    used_now = used_next;
}

fn planeHbl(fb: *zg.LogicalFB, _: *zg.ZigOS, line: u16, _: u16) void {
    if (line >= PH) return;
    for (buf.now[line][0..used_now[line]], 0..) |c, i| fb.palette[i] = c;
}

fn borderHbl(zigos: *zg.ZigOS, line: u16) void {
    zigos.setBackgroundColor(zg.Color.fromRGBA(c0_next[@min(line, PH - 1)]));
}
