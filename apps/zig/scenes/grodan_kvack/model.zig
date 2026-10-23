// --------------------------------------------------------------------------
// grodan_kvack -- the demo's own animation state, and the composer that paints
// it into one 320x200 palette-index plane. This IS the Go's Update()/Draw(),
// transcribed to integer/fixed-point:
//
//   * moveY/moveX/X/Y are the Go's float64s rewritten as the integers they
//     always hold (they only ever step by whole pixels). The two float flags
//     the Go gates them on -- `bgcount` (a 0.1/tick counter vs >10 and >20) and
//     `ychange` (a +/-0.1/tick accumulator vs +/-50) -- become counters whose
//     thresholds are the EXACT ticks the float comparison first fires at
//     (bgcount ticks 101/200; ychange tenths 500/-500 -- checked against a
//     float64 replay for 6000 ticks).
//   * swing/swingy are the Go's radians as zg.fixtrig u32 angles (0.02/0.03 a
//     tick), and the sprite corner is Q16.16; the only difference from the Go's
//     float is <= 1 px on ~0.3% of sprite corners (fixtrig's interpolation),
//     the port's own pixel quantisation.
//   * the four scroll positions are the pixels they always are; speed and
//     reset are the Go's (a horizontal scroll restarts at 640 -- its font-px
//     units -- which is the Go's screenWidth).
//
// Draw order is the Go's: bgGreen, bgPink, 12 sprites, big, vertical, small.
// Every layer is the Go art at half scale (see assets.zig).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const fixtrig = zg.fixtrig;
const assets = @import("assets.zig");

pub const W = 320;
pub const H = 200;

const ANG_002 = fixtrig.angle(0.02);
const ANG_003 = fixtrig.angle(0.03);

/// cos/sin of the 12 sprite phases (i*0.2 rad), the Go's spritePhaseCos/Sin.
const PHASE: [12][2]i32 = blk: {
    var t: [12][2]i32 = undefined;
    for (&t, 0..) |*v, i| {
        const a = fixtrig.angle(@as(f64, @floatFromInt(i)) * 0.2);
        v.* = .{ fixtrig.cos(a), fixtrig.sin(a) };
    }
    break :blk t;
};

/// The six x positions the Go draws its vertical-text canvas at (halved).
pub const VERT_X = [6]i32{ 0, 32, 64, 240, 272, 304 };

/// The Go's ScrollText, integer state.
pub const Scroll = struct {
    cells: []const u8,
    adv: i32,
    speed: i32,
    vertical: bool,
    content: i32,
    scroll: i32,

    fn make(cells: []const u8, adv: i32, speed: i32, vertical: bool, scroll: i32) Scroll {
        return .{
            .cells = cells,
            .adv = adv,
            .speed = speed,
            .vertical = vertical,
            .content = adv * @as(i32, @intCast(cells.len)),
            .scroll = scroll,
        };
    }

    fn update(self: *Scroll) void {
        if (self.vertical) {
            self.scroll += self.speed;
            if (self.scroll > self.content + 400) self.scroll = -100;
        } else {
            self.scroll -= self.speed;
            if (self.scroll < -self.content) self.scroll = 640;
        }
    }
};

pub const State = struct {
    moveY: i32,
    howmuchY: i32,
    moveX: i32,
    howmuchX: i32,
    bgcount: i32,
    Y: i32,
    hY: i32,
    X: i32,
    gox: i32,
    ychange10: i32, // the Go's ychange, in tenths
    addy10: i32,
    swing: fixtrig.Angle,
    swingy: fixtrig.Angle,
    s1: Scroll, // mainText   (big, horizontal)
    s2: Scroll, // vertText   (vertical)
    s3: Scroll, // smallText1 (small, horizontal)
    s4: Scroll, // smallText2 (small, horizontal)

    pub fn init() State {
        return .{
            .moveY = 0,
            .howmuchY = 1,
            .moveX = 0,
            .howmuchX = 1,
            .bgcount = 0,
            .Y = 0,
            .hY = 1,
            .X = 0,
            .gox = 0,
            .ychange10 = 0,
            .addy10 = 1,
            .swing = 0,
            .swingy = 0,
            .s1 = Scroll.make(assets.main_cells, 24, 2, false, 0),
            .s2 = Scroll.make(assets.vert_cells, 29, 3, true, -100),
            .s3 = Scroll.make(assets.small1_cells, 8, 1, false, 0),
            .s4 = Scroll.make(assets.small2_cells, 8, 2, false, 0),
        };
    }

    /// The Go's Update(), one 60 Hz tick.
    pub fn update(self: *State) void {
        self.bgcount += 1;
        if (self.moveY < -400) self.howmuchY = 1;
        if (self.moveY > 0) self.howmuchY = -1;
        self.moveY += self.howmuchY;
        if (self.bgcount >= 101) {
            if (self.moveX < -640 * 2) self.howmuchX = 16;
            if (self.moveX > 0) self.howmuchX = -16;
            self.moveX += self.howmuchX;
        }
        if (self.bgcount >= 200) self.bgcount = 0;

        if (self.Y < -400) {
            self.hY = 2;
            self.gox = 16;
        }
        if (self.Y > 0) {
            self.hY = -2;
            self.gox = -16;
        }
        self.X += self.gox;
        if (self.X < -710) self.X = -710;
        if (self.X > 0) self.X = 0;
        self.Y += self.hY;

        if (self.ychange10 >= 500) self.addy10 = -1;
        if (self.ychange10 <= -500) self.addy10 = 1;
        self.ychange10 += self.addy10;

        self.swing +%= ANG_002;
        self.swingy +%= ANG_003;

        self.s1.update();
        self.s3.update();
        self.s4.update();
        self.s2.update();
    }

    // ---- Draw ---------------------------------------------------------------

    pub fn compose(self: *const State, fb: []u8) void {
        @memset(fb[0 .. W * H], assets.BLACK);
        tile(fb, assets.bg_green, assets.BG_W, assets.BG_H, assets.GREEN, self.moveX, self.moveY);
        tile(fb, assets.bg_pink, assets.BG_W, assets.BG_H, assets.PINK, self.X, self.Y);
        self.drawSprites(fb);
        self.drawBig(fb);
        self.drawVert(fb);
        self.drawSmall(fb, &self.s3, 8);
        self.drawSmall(fb, &self.s4, 32);
    }

    /// Sprite i's top-left corner, in screen pixels.
    pub fn spriteAt(self: *const State, i: usize) [2]i32 {
        const cosSwing = fixtrig.cos(self.swing);
        const sinSwing = fixtrig.sin(self.swing);
        const sinY = fixtrig.sin(self.swingy);
        const cosY = fixtrig.cos(self.swingy);
        const cs = fixtrig.mul(cosSwing, PHASE[i][0]) + fixtrig.mul(sinSwing, PHASE[i][1]);
        const ssy = fixtrig.mul(sinY, PHASE[i][0]) - fixtrig.mul(cosY, PHASE[i][1]);
        // our x = 152 + 145*cosSwing; our y = 50 + ychange*(ssy+sinY)/2,
        // ychange in tenths: ychange10*S/20 in Q16.16.
        const xq: i32 = (152 << 16) + 145 * cs;
        const yq: i32 = (50 << 16) + @divFloor(self.ychange10 * (ssy + sinY), 20);
        return .{ roundq16(xq), roundq16(yq) };
    }

    fn drawSprites(self: *const State, fb: []u8) void {
        var i: usize = 0;
        while (i < 12) : (i += 1) {
            const at = self.spriteAt(i);
            const x0 = at[0];
            const y0 = at[1];
            var sy: usize = 0;
            while (sy < assets.SPRITE_H) : (sy += 1) {
                const y = y0 + @as(i32, @intCast(sy));
                if (y < 0 or y >= H) continue;
                var sx: usize = 0;
                while (sx < 16) : (sx += 1) {
                    const x = x0 + @as(i32, @intCast(sx));
                    if (x < 0 or x >= W) continue;
                    if (assets.bit(assets.sprite, i * assets.SPRITE_STRIDE + sx, sy, assets.SPRITE_W) != 0)
                        fb[@as(usize, @intCast(y)) * W + @as(usize, @intCast(x))] = assets.SPRITE;
                }
            }
        }
    }

    fn drawBig(self: *const State, fb: []u8) void {
        const s = &self.s1;
        var k: usize = 0;
        while (k < s.cells.len) : (k += 1) {
            const xgo = (s.scroll + @as(i32, @intCast(k)) * 24) * 4;
            if (xgo + 96 <= 0) continue;
            if (xgo >= W) break;
            const c = s.cells[k];
            if (c != 0xFF) glyphBig(fb, c, xgo);
        }
    }

    fn drawVert(self: *const State, fb: []u8) void {
        const s = &self.s2;
        const base = 400 - s.scroll;
        var k: usize = 0;
        while (k < s.cells.len) : (k += 1) {
            const ygo = base + @as(i32, @intCast(k)) * 29;
            if (ygo + 29 <= 0) continue;
            if (ygo >= 400) break;
            const c = s.cells[k];
            if (c == 0xFF) continue;
            const y0 = @divFloor(ygo, 2);
            for (VERT_X) |xc| glyphUp(fb, c, xc, y0);
        }
    }

    fn drawSmall(self: *const State, fb: []u8, s: *const Scroll, y0: i32) void {
        _ = self;
        var k: usize = 0;
        while (k < s.cells.len) : (k += 1) {
            const x = s.scroll + @as(i32, @intCast(k)) * 8;
            if (x + 8 <= 0) continue;
            if (x >= W) break;
            const c = s.cells[k];
            if (c != 0xFF) glyphSmall(fb, c, x, y0);
        }
    }
};

inline fn roundq16(v: i32) i32 {
    return @divFloor(v + 32768, 65536);
}

/// Draw a whole 1-bit mask at (dx, dy), clipped, in `color` (Go paste()).
fn tile(fb: []u8, mask: []const u8, mw: usize, mh: usize, color: u8, ox: i32, oy: i32) void {
    const x_off = @divFloor(ox, 2);
    const y_off = @divFloor(oy, 2);
    var yy: i32 = 0;
    while (yy < 2) : (yy += 1) {
        const ty = y_off + 200 * yy;
        if (ty >= H or ty + @as(i32, @intCast(mh)) <= 0) continue;
        var xx: i32 = 0;
        while (xx < 3) : (xx += 1) {
            const tx = x_off + W * xx;
            if (tx >= W or tx + @as(i32, @intCast(mw)) <= 0) continue;
            blitMask(fb, mask, mw, mh, color, tx, ty);
        }
    }
}

fn blitMask(fb: []u8, mask: []const u8, mw: usize, mh: usize, color: u8, dx: i32, dy: i32) void {
    const x0 = @max(dx, 0);
    const y0 = @max(dy, 0);
    const x1 = @min(dx + @as(i32, @intCast(mw)), W);
    const y1 = @min(dy + @as(i32, @intCast(mh)), H);
    if (x1 <= x0 or y1 <= y0) return;
    var y: i32 = y0;
    while (y < y1) : (y += 1) {
        const my: usize = @intCast(y - dy);
        var x: i32 = x0;
        while (x < x1) : (x += 1) {
            if (assets.bit(mask, @intCast(x - dx), my, mw) != 0)
                fb[@as(usize, @intCast(y)) * W + @as(usize, @intCast(x))] = color;
        }
    }
}

/// One big-font glyph, drawn into the big canvas (Go Scale(8,6), sampled 4:3).
fn glyphBig(fb: []u8, cell: u8, x0: i32) void {
    const col: usize = cell % 10;
    const row: usize = cell / 10;
    var dy: usize = 0;
    while (dy < 99) : (dy += 1) {
        const srcrow = row * 33 + dy / 3;
        var dx: usize = 0;
        while (dx < 96) : (dx += 1) {
            const x = x0 + @as(i32, @intCast(dx));
            if (x < 0 or x >= W) continue;
            if (assets.bit(assets.bsfont, col * 24 + dx / 4, srcrow, assets.BSF_W) != 0)
                fb[(100 + dy) * W + @as(usize, @intCast(x))] = assets.BIG;
        }
    }
}

/// One vertical-font glyph (Go Scale(1,1) into a 32x400 canvas, shown halved).
fn glyphUp(fb: []u8, cell: u8, x0: i32, y0: i32) void {
    const col: usize = cell % 10;
    const row: usize = cell / 10;
    var dy: usize = 0;
    while (dy < 15) : (dy += 1) {
        const y = y0 + @as(i32, @intCast(dy));
        if (y < 0 or y >= H) continue;
        const srcrow = row * 29 + 2 * dy;
        var dx: usize = 0;
        while (dx < 16) : (dx += 1) {
            const x = x0 + @as(i32, @intCast(dx));
            if (x < 0 or x >= W) continue;
            if (assets.bit(assets.upfont, col * 33 + 2 * dx, srcrow, assets.UPF_W) != 0)
                fb[@as(usize, @intCast(y)) * W + @as(usize, @intCast(x))] = assets.VERT;
        }
    }
}

/// One small-font glyph (Go Scale(1,1), shown 1:1).
fn glyphSmall(fb: []u8, cell: u8, x0: i32, y0: i32) void {
    const col: usize = cell % 10;
    const row: usize = cell / 10;
    var dy: usize = 0;
    while (dy < 8) : (dy += 1) {
        const y = y0 + @as(i32, @intCast(dy));
        if (y < 8 or y >= 40) continue;
        var dx: usize = 0;
        while (dx < 8) : (dx += 1) {
            const x = x0 + @as(i32, @intCast(dx));
            if (x < 0 or x >= W) continue;
            if (assets.bit(assets.lfont, col * 8 + dx, row * 8 + dy, assets.LF_W) != 0)
                fb[@as(usize, @intCast(y)) * W + @as(usize, @intCast(x))] = assets.SMALL;
        }
    }
}

// ---- the per-line rasters ----------------------------------------------------
/// Fill the three copper tables (visible rows) from the .pal files, exactly the
/// per-canvas row colours the Go's source-atop masks produce:
///   BIG   rows 100..195 = bigraster rows 0..95; rows 196..199 = white (the
///         raster covers only the canvas' first 192 rows; the glyphs' own white
///         shows through below it).
///   VERT  every row 0..199 = upraster rows 0..199.
///   SMALL rows 8..15 = upraster rows 16..19 doubled; rows 32..39 = rows 64..67
///         doubled (the two 4-row subimages the Go scales by 2).
pub fn fillRasters(big: []u32, vert: []u32, small: []u32) void {
    for (0..H) |y| {
        vert[y] = assets.UP_ROWS[y];
        big[y] = if (y >= 100 and y < 196)
            assets.BIG_ROWS[y - 100]
        else if (y >= 196)
            assets.PALETTE[assets.WHITE].toRGBA()
        else
            assets.PALETTE[assets.BLACK].toRGBA();
        small[y] = if (y >= 8 and y < 16)
            assets.UP_ROWS[16 + (y - 8) / 2]
        else if (y >= 32 and y < 40)
            assets.UP_ROWS[64 + (y - 32) / 2]
        else
            assets.PALETTE[assets.BLACK].toRGBA();
    }
}
