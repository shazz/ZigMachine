// TCB #2's 400x240 `orgcanvas`, rebuilt every frame exactly as do_tcb2 does:
//   fill black; scroller(0) (the cylinder's back faces); otherscroller() (the
//   48-wide font at y 155); two scrolledge.png at 0.7x on (9|310, 165-Y);
//   scroller(1) (the front faces); a black quad (318,111,50,130).
// scroller(ab): the 704x50 buffer gets the 32x25 text at y 0, its top half
// copied to the bottom, and raster_2.png 'source-atop' at alpha 0.4 over it
// (the tint table); then twelve 32-px columns, column i squashed by
// -sin(rota + 0.4 i) about y 168 + 30 cos(rota + 0.4 i): negative = a back
// face (bottom half, flipped, drawn by ab 0), positive = a front face (top half, ab 1).
// Every draw is nearest (the remake's canvas smooths).
const gen = @import("assets_gen.zig");
const assets = @import("assets.zig");
const image = @import("image.zig");
const sc = @import("scroller.zig");

const ifloor = image.ifloor;
const NONE = image.NONE;

const ROTA_STEP: f64 = 0.02;

pub const W = 400;
pub const H = 240;
/// Only rows TOP..H are stored: the layer's 1.8x draw never samples above
/// orgcanvas row 111 ((0 + 0.5 + 200) / 1.8), and nothing is drawn there
/// either (the cylinder's highest row is floor(138 - 0.5 - 25) - 1 = 111).
pub const TOP = 111;
/// TCB #2's scratch in the part buffer: the stored orgcanvas rows, and the text
/// half of the 704x50 buffer as kh LOCAL indices (the bottom half is the same
/// pixels; only the tint row differs).
pub const Scratch = struct {
    rows: [H - TOP][W]u16,
    sbuf: [25][704]u8,
};

/// orgcanvas row `y`, TOP <= y < H.
pub fn row(y: usize) *[W]u16 {
    return &assets.scratch(.tcb2).rows[y - TOP];
}

pub const Cylinder = struct {
    rota: f64,
    counter: i32,

    /// scroller(ab): the text is drawn again (it advances every call).
    pub fn scroller(self: *Cylinder, text: *sc.Scroller, ab: u1) void {
        fillBuffer(text);
        if (ab == 0) self.rota -= 0.12;
        self.counter += 2;
        for (0..12) |iu| {
            const i: i32 = @intCast(iu);
            const a = self.rota + @as(f64, @floatFromInt(i)) * 0.4;
            const size = -1 * @sin(a);
            const yrot = 30 * @cos(a);
            if (self.counter > 31) {
                self.counter = 0;
                self.rota += ROTA_STEP * 20; // rota += 0.02*20
            }
            if (size < 0 and ab == 0) column(i, self.counter, yrot, size, 25);
            if (size > 0 and ab == 1) column(i, self.counter, yrot, size, 0);
        }
    }
};

fn fillBuffer(text: *sc.Scroller) void {
    const sbuf = &assets.scratch(.tcb2).sbuf;
    for (sbuf) |*r| @memset(r, 0);
    text.advance();
    for (0..text.wide + 1) |k| {
        const nb: i32 = @as(i32, text.ltr[k]) - 32;
        const party = @divFloor(nb, 8) * 25;
        if (party >= 200) continue;
        const partx = @mod(nb, 8) * 32;
        const px: i32 = @intFromFloat(text.posx[k]);
        var c: i32 = @max(0, px);
        while (c < px + 32 and c < 704) : (c += 1) {
            for (0..25) |r| sbuf[r][@intCast(c)] = assets.kh.local(@intCast(partx + c - px), @intCast(party + @as(i32, @intCast(r))));
        }
    }
}

/// scrollbuffercanvas.drawPart(orgcanvas, -32+32i-counter, yrot+200-32,
///   32i-counter, party, 32, 25, 1, 0, 1, size)
fn column(i: i32, counter: i32, yrot: f64, size: f64, party: i32) void {
    var dx = -32 + 32 * i - counter;
    var partx = 32 * i - counter;
    var partw: i32 = 32;
    if (partx < 0) {
        dx -= partx;
        partw += partx;
        partx = 0;
    } else partw = @min(partw, 704 - partx);
    if (partw <= 0) return;
    const dy = yrot + 200 - 32;
    const lo = ifloor(dy - 0.5 + 25 * @min(size, 0)) - 1;
    const hi = ifloor(dy - 0.5 + 25 * @max(size, 0)) + 2;
    const s = assets.scratch(.tcb2);
    var y = @max(lo, TOP);
    while (y < @min(hi, H)) : (y += 1) {
        const v = ifloor((@as(f64, @floatFromInt(y)) + 0.5 - dy) / size);
        if (v < 0 or v >= 25) continue;
        const src = &s.sbuf[@intCast(v)];
        const tint = &gen.tint_gid[@intCast(party + v)];
        const dst = &s.rows[@intCast(y - TOP)];
        var x = @max(dx, 0);
        while (x < dx + partw and x < W) : (x += 1) {
            const l = src[@intCast(partx + x - dx)];
            if (l != 0) dst[@intCast(x)] = tint[l];
        }
    }
}

/// otherscroller(): the 48x25 font into the 329x150 canvas at y 0, drawn at (0,155).
pub fn otherScroller(text: *sc.Scroller) void {
    text.advance();
    for (0..text.wide + 1) |k| {
        const nb: i32 = @as(i32, text.ltr[k]) - 32;
        const party = @divFloor(nb, 8) * 25;
        if (party >= 200) continue;
        const partx = @mod(nb, 8) * 48;
        const px: i32 = @intFromFloat(text.posx[k]);
        var c: i32 = @max(0, px);
        while (c < px + 48 and c < 329) : (c += 1) {
            for (0..25) |r| {
                const g = assets.kh2.at(partx + c - px, party + @as(i32, @intCast(r)));
                if (g != NONE) row(155 + r)[@intCast(c)] = g;
            }
        }
    }
}

/// scrolledge.draw(orgcanvas, cx, cy, 1, 0, 0.7, 0.7), midhandled (13, 18).
pub fn edge(cx: f64, cy: f64) void {
    var y: i32 = @max(TOP, ifloor(cy - 20));
    while (y < @min(H, ifloor(cy + 20))) : (y += 1) {
        const v = ifloor((@as(f64, @floatFromInt(y)) + 0.5 - cy) / 0.7 + 18);
        var x: i32 = @max(0, ifloor(cx - 16));
        while (x < ifloor(cx + 16)) : (x += 1) {
            const u = ifloor((@as(f64, @floatFromInt(x)) + 0.5 - cx) / 0.7 + 13);
            const g = assets.edge.at(u, v);
            if (g != NONE) row(@intCast(y))[@intCast(x)] = g;
        }
    }
}

pub fn clear() void {
    for (&assets.scratch(.tcb2).rows) |*r| @memset(r, 0);
}

/// orgcanvas.quad(318, 111, 50, 130, '#000000')
pub fn quad() void {
    for (TOP..H) |y| @memset(row(y)[318..368], 0);
}
