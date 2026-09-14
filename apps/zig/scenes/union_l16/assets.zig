// --------------------------------------------------------------------------
// LEVEL 16 assets: the layout of l16.bin (tools/private_tools/union_l16_assets.py),
// the geometry that maps screen.js's 832x572 canvas onto the 400x280 overscan
// planes, and the CurveRipper sprite tables.
//
// Geometry: the canvas is a 416x286 ST fullscreen, doubled. The planes show canvas
// x 16..815 and y 6..565, 8 ST columns and 3 ST rows cropped off each side: plane
// pixel (X, Y) is canvas pixel (2X + 16, 2Y + 6). The centred crop is Matt's
// decision (2026-09-14): the picture fills all 416x286, so something has to go.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const blit = zg.blit;

pub const W = 400;
pub const H = 280;
pub const CROP_X = 16; // canvas columns left of plane column 0
pub const CROP_Y = 6; // canvas rows above plane row 0

/// The canvas row plane row `y` shows.
pub fn canvasRow(y: usize) i32 {
    return @intCast(2 * y + CROP_Y);
}

/// The plane column of an even canvas column.
pub fn planeX(canvas_x: i32) i32 {
    return @divExact(canvas_x - CROP_X, 2);
}

pub const BOB_W = 16; // union_bob.png 32x33, even rows and columns
pub const BOB_H = 17;
pub const FONT_W = 256; // font.png 512x128: even columns, every row
pub const FONT_H = 128;
pub const RASTER_ROWS = 304; // raster.png 160x304, one colour a row
pub const WATER_ROWS = 408; // watergrad2.png 80x408, one colour a row

pub const TOTAL = W * H + BOB_W * BOB_H + FONT_W * FONT_H + 3 * (RASTER_ROWS + WATER_ROWS);

/// Index 0 transparent: the picture's holes and the bob's field.
pub const picture_palette = zg.convertU8ArraytoColors(@embedFile("../../assets/screens/union_l16/pal_picture.dat"));
/// Index 0 transparent (black once premultiplied), then font.png's inks, as RGBA bytes.
pub const FONT_PALETTE = @embedFile("../../assets/screens/union_l16/pal_font.dat");

pub fn fontInk(index: u8) [3]u8 {
    return FONT_PALETTE[@as(usize, index) * 4 ..][0..3].*;
}

pub const Images = struct {
    picture: []const u8,
    bob: blit.Image,
    font: []const u8,
    raster: []const u8, // RGB, RASTER_ROWS rows
    water: []const u8, // RGB, WATER_ROWS rows

    /// Views into the depacked blob; `buf` must be TOTAL bytes.
    pub fn split(buf: []const u8) Images {
        var at: usize = 0;
        const take = struct {
            fn f(b: []const u8, pos: *usize, n: usize) []const u8 {
                defer pos.* += n;
                return b[pos.*..][0..n];
            }
        }.f;
        return .{
            .picture = take(buf, &at, W * H),
            .bob = blit.Image.init(take(buf, &at, BOB_W * BOB_H), BOB_W),
            .font = take(buf, &at, FONT_W * FONT_H),
            .raster = take(buf, &at, 3 * RASTER_ROWS),
            .water = take(buf, &at, 3 * WATER_ROWS),
        };
    }
};

// screen.js:36-41, verbatim in curve.txt: 982 positions "ripped in ST resolution".
pub const CURVE_LEN = 982;
pub const curve_x = parseCurve("spritePosX");
pub const curve_y = parseCurve("spritePosY");

fn parseCurve(comptime name: []const u8) [CURVE_LEN]i32 {
    @setEvalBranchQuota(200_000);
    const text = @embedFile("../../assets/screens/union_l16/curve.txt");
    const key = name ++ " = ";
    const start = (std.mem.indexOf(u8, text, key) orelse @compileError("curve.txt: no " ++ name)) + key.len;
    const end = std.mem.indexOfScalarPos(u8, text, start, '\n') orelse text.len;
    var out: [CURVE_LEN]i32 = undefined;
    var n: usize = 0;
    var it = std.mem.tokenizeAny(u8, text[start..end], ", ");
    while (it.next()) |tok| : (n += 1) {
        if (n == CURVE_LEN) @compileError("curve.txt: too many values in " ++ name);
        out[n] = std.fmt.parseInt(i32, tok, 10) catch @compileError("curve.txt: bad value in " ++ name);
    }
    if (n != CURVE_LEN) @compileError("curve.txt: too few values in " ++ name);
    return out;
}
