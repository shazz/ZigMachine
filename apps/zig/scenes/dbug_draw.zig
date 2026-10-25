// --------------------------------------------------------------------------
// D-BUG screen — pixel helpers, split out of dbug.zig for the file-size budget
// (same arrangement as st_replay's draw/ui split).
// --------------------------------------------------------------------------
const zg = @import("zigos");

const RenderTarget = zg.RenderTarget;

pub const OVERSCAN_W: u16 = 400;
pub const ZOOM: u16 = 8;

pub const OVERSCAN_H: u16 = 280;

/// The rows of the overscan page that hold anything but colour 0. The page is
/// cleared and copied out only over this band (it used to be all 280 rows, twice
/// a frame, as byte loops), which is where the picture is, plus where it was.
pub const Dirty = struct {
    lo: u16 = 0,
    hi: u16 = OVERSCAN_H,

    pub fn rows(lo: i32, hi: i32) Dirty {
        return .{ .lo = @intCast(@max(lo, 0)), .hi = @intCast(@min(hi, OVERSCAN_H)) };
    }
    pub fn merge(a: Dirty, b: Dirty) Dirty {
        return .{ .lo = @min(a.lo, b.lo), .hi = @max(a.hi, b.hi) };
    }
};

/// The rows of `prev` that the new frame does not repaint anyway (`band` is
/// rewritten in full by zoomScroller): at most two runs, empty ones lo >= hi.
pub fn staleRuns(prev: Dirty, band: Dirty) [2]Dirty {
    if (prev.lo >= prev.hi) return .{ .{ .lo = 0, .hi = 0 }, .{ .lo = 0, .hi = 0 } };
    const a = prev.lo;
    const b = @min(prev.hi, @max(band.lo, a));
    const c = @max(prev.lo, band.hi);
    return .{ .{ .lo = a, .hi = b }, .{ .lo = c, .hi = prev.hi } };
}

/// Zero the stale rows on the CPU (the native test's reference; the cart fills
/// them with CHISEL).
pub fn clearStale(page: []u8, prev: Dirty, band: Dirty) void {
    for (staleRuns(prev, band)) |r| {
        if (r.hi > r.lo) @memset(page[@as(u32, r.lo) * OVERSCAN_W .. @as(u32, r.hi) * OVERSCAN_W], 0);
    }
}

/// Blow the narrow scrolltext strip up by ZOOM in both axes into the overscan
/// page (the plane itself in the cart), its top edge at `top`. The strip is
/// rendered 50 pixels wide precisely so that 50*8 == 400 covers the opened
/// borders as well. Each zoomed line is built once as 100 words in a local, then
/// stored on its 8 page rows (page must be 4-aligned: a plane is) through a
/// volatile pointer: as a plain loop LLVM turns that copy into a memcpy (~11
/// cycles a word on the board), this is a load and a posted store a word.
///
/// All CPU: it used to store the first row and let CHISEL repeat it (a stride-0
/// blit) over the other seven, but that source row lies in the plane the blit
/// writes, and CHISEL's overlap check (measured from the plane's base) then runs
/// the op ORDERED, each read waiting for the previous write: ~2 Mc a frame on
/// the board for 24 such blits (cart_c 2.33 Mc, 33.5 fps).
pub fn zoomScroller(page: []u8, src: RenderTarget, top: u16, rows: u16) void {
    const strip = src.render_buffer;
    const words: [*]volatile u32 = @ptrCast(@alignCast(page.ptr));
    var line: [LINE_WORDS]u32 = undefined;
    var char_row: u32 = 0;
    while (char_row < rows) : (char_row += 1) {
        const y0 = @as(u32, top) + char_row * ZOOM;
        if (y0 >= OVERSCAN_H) return;
        buildLine(&line, strip.buffer[char_row * strip.width ..][0..strip.width]);
        const y1 = @min(y0 + ZOOM, OVERSCAN_H);
        var y = y0;
        while (y < y1) : (y += 1) storeLine(words + y * LINE_WORDS, &line);
    }
}

const LINE_WORDS = OVERSCAN_W / 4;

/// One zoomed line: each strip pixel as 8 equal pixels, two words a pixel.
fn buildLine(line: *[LINE_WORDS]u32, strip_row: []const u8) void {
    for (strip_row, 0..) |pal_entry, col| {
        const v = @as(u32, pal_entry) * 0x01010101;
        line[col * 2] = v;
        line[col * 2 + 1] = v;
    }
}

fn storeLine(dst: [*]volatile u32, line: *const [LINE_WORDS]u32) void {
    var i: usize = 0;
    while (i < LINE_WORDS) : (i += 4) {
        inline for (0..4) |k| dst[i + k] = line[i + k];
    }
}
