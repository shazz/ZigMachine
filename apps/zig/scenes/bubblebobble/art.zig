// --------------------------------------------------------------------------
// BUBBLE BOBBLE — drawing. The Go draws on a 768x720 canvas: a 768x624
// playfield (32x26 tiles of 24px) between two 48px HUD strips, plus sprite
// art of its own size scaled at draw time (drawImage in render.go). The cart
// uses ONE 400x280 overscan plane and maps that canvas by /3 — the playfield
// lands at (72,36) and is then EXACTLY the arcade's 32x26 tiles of 8px — while
// the surrounding borders carry the HUD, the menus and the banners, where the
// ST's 8x8 system font is actually readable.
//
// Sprites keep the art's native pixel size and are scaled to the Go's draw
// size here, nearest-neighbour, keyed on palette index 0. Tiles and the logo
// arrived pre-scaled (8x8 and 117x84) from tools/bubblebobble/bb_assets.py.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const assets = @import("assets.zig");

pub const SCR_W: i32 = 400;
pub const SCR_H: i32 = 280;

// The Go's playfield, /3 and centred: 768/3 = 256 wide, 624/3 = 208 tall.
pub const PLAY_X: i32 = 72;
pub const PLAY_Y: i32 = 36;
pub const PLAY_W: i32 = 256;
pub const PLAY_H: i32 = 208;

// Go canvas coordinates -> cart pixels (the /3 map, origin at the canvas top-left).
// Integer only: a Q16.16 world coordinate drops to whole Go pixels then to cart pixels.
pub const CANVAS_X: i32 = 72;
pub const CANVAS_Y: i32 = 20;
pub inline fn sx(v: i32) i32 {
    return CANVAS_X + @divTrunc(v >> 16, 3);
}
pub inline fn sy(v: i32) i32 {
    return CANVAS_Y + @divTrunc(v >> 16, 3);
}

var fb: *zg.LogicalFB = undefined;

pub fn setup(zigos: *zg.ZigOS) void {
    fb = &zigos.lfbs[0];
    fb.is_enabled = true;
    fb.openBorders(.all); // the whole 400x280 is ours
    fb.setPalette(assets.PALETTE);
    fb.setPaletteEntry(0, .{ .r = 0, .g = 0, .b = 0, .a = 0 });
    zigos.setBackgroundColor(assets.PALETTE[0]);
}

pub fn clear() void {
    const n: usize = @as(usize, fb.fb_w) * fb.fb_h;
    @memset(fb.fb[0..n], assets.INK);
}

/// The plane's pixel buffer and stride, for the headless harness.
pub fn screenPtr() [*]u8 {
    return fb.fb;
}
pub fn screenStride() u32 {
    return fb.stride;
}
pub fn palettePtr() [*]u32 {
    return fb.palette;
}

pub fn box(x: i32, y: i32, w: i32, h: i32, c: u8) void {
    if (w <= 0 or h <= 0) return;
    var yy = @max(0, y);
    const y2 = @min(SCR_H, y + h);
    const x0: usize = @intCast(@max(0, x));
    const x1: usize = @intCast(@min(SCR_W, x + w));
    while (yy < y2) : (yy += 1) {
        const row = @as(usize, @intCast(yy)) * fb.stride;
        @memset(fb.fb[row + x0 .. row + x1], c);
    }
}

pub inline fn px(x: i32, y: i32, c: u8) void {
    if (x < 0 or y < 0 or x >= SCR_W or y >= SCR_H) return;
    fb.fb[@as(usize, @intCast(y)) * fb.stride + @as(usize, @intCast(x))] = c;
}

// --- animation lookup (all comptime: the names never reach run time) --------
fn AnimIdx(comptime name: []const u8) comptime_int {
    @setEvalBranchQuota(200000);
    for (assets.ANIMS, 0..) |a, i| {
        if (std.mem.eql(u8, a.name, name)) return i;
    }
    @compileError("bubblebobble: no animation named " ++ name);
}

pub const Kind = enum(u8) { zenchan = 0, monsta = 1, mighta = 2, pulpul = 3, banebou = 4, invader = 5 };

fn kindTable(comptime state: []const u8) [6]u8 {
    const names = [_][]const u8{ "zenchan", "monsta", "mighta", "pulpul", "banebou", "invader" };
    var out: [6]u8 = undefined;
    for (names, 0..) |n, i| out[i] = AnimIdx(n ++ "/" ++ state);
    return out;
}

pub const WALK = kindTable("walk");
pub const ANGRY = kindTable("angry");
pub const DEAD = kindTable("dead");
pub const BUBBLE_ANIM = kindTable("bubble");
pub const WARNING = kindTable("warning");
pub const ESCAPE = kindTable("escape");

pub const MIGHTA_SHOOT = AnimIdx("mighta/shoot");
pub const MIGHTA_SHOOT_ANGRY = AnimIdx("mighta/shoot-angry");

pub const PLAYER = [2][4]u8{
    .{ AnimIdx("green/walk"), AnimIdx("green/jump"), AnimIdx("green/shoot"), AnimIdx("green/dead") },
    .{ AnimIdx("blue/walk"), AnimIdx("blue/jump"), AnimIdx("blue/shoot"), AnimIdx("blue/dead") },
};

pub const BUBBLE = AnimIdx("bubble");
pub const BUBBLE_WARNING = AnimIdx("bubble-warning");
pub const ELEMENT_BUBBLE = [4]u8{ 0, AnimIdx("water-bubble"), AnimIdx("thunder-bubble"), AnimIdx("fire-bubble") };

pub const BOULDER = AnimIdx("boulder");
pub const LASER = AnimIdx("laser");
pub const POP = AnimIdx("pop");

pub const ELEM = [4]u8{ 0, AnimIdx("water"), AnimIdx("thunder"), AnimIdx("fire") };
pub const FLAME = AnimIdx("flame");

pub const FOOD = blk: {
    var t: [25]u8 = undefined;
    for (0..25) |i| t[i] = AnimIdx(std.fmt.comptimePrint("food/{d}", .{i + 1}));
    break :blk t;
};

pub const POWER = [13]u8{
    0,                         AnimIdx("pink_candy"),
    AnimIdx("blue_candy"),     AnimIdx("yellow_candy"),
    AnimIdx("shoes"),          AnimIdx("orange_parasol"),
    AnimIdx("red_parasol"),    AnimIdx("purple_parasol"),
    AnimIdx("crystal_ring"),   AnimIdx("amethyst_ring"),
    AnimIdx("ruby_ring"),      AnimIdx("dynamite"),
    AnimIdx("clock"),
};

/// The Go's artwork.frame: the frame advances every 10 ticks of the 60 Hz world.
pub inline fn frameOf(idx: u8, tick: i32) u16 {
    const info = assets.ANIMS[idx];
    const t: u32 = @intCast(if (tick < 0) 0 else tick);
    return info.first + @as(u16, @intCast((t / 10) % info.count));
}

/// One sprite, scaled from its native size to `w` x `h`, index 0 transparent.
/// `flip` mirrors it right-to-left, as the Go's drawImage does for dir < 0.
pub fn sprAt(idx: u8, tick: i32, x: i32, y: i32, w: i32, h: i32, flip: bool) void {
    const f = assets.FRAMES[frameOf(idx, tick)];
    const sw: i32 = f.w;
    const sh: i32 = f.h;
    if (w <= 0 or h <= 0) return;
    const src = assets.FRAMES_BIN[@as(usize, f.off)..][0..@intCast(sw * sh)];
    var yy: i32 = 0;
    while (yy < h) : (yy += 1) {
        const dy = y + yy;
        if (dy < 0 or dy >= SCR_H) continue;
        const syy: i32 = @intCast(@divTrunc(@as(i64, yy) * sh, h));
        const dst_row = @as(usize, @intCast(dy)) * fb.stride;
        var xx: i32 = 0;
        while (xx < w) : (xx += 1) {
            const dx = x + xx;
            if (dx < 0 or dx >= SCR_W) continue;
            const sxr: i32 = @intCast(@divTrunc(@as(i64, xx) * sw, w));
            const sxi = if (flip) sw - 1 - sxr else sxr;
            const c = src[@as(usize, @intCast(syy * sw + sxi))];
            if (c != 0) fb.fb[dst_row + @as(usize, @intCast(dx))] = c;
        }
    }
}

pub fn spr(idx: u8, tick: i32, x: i32, y: i32, size: i32, dir: i32) void {
    sprAt(idx, tick, x, y, size, size, dir > 0);
}

/// A tile (the generated 8x8 set, 1..25).
pub fn tile(n: u8, x: i32, y: i32) void {
    if (n == 0 or n > 25) return;
    const src = assets.TILES_BIN[@as(usize, n - 1) * 64 ..][0..64];
    var yy: i32 = 0;
    while (yy < 8) : (yy += 1) {
        const dy = y + yy;
        if (dy < 0 or dy >= SCR_H) continue;
        const dst_row = @as(usize, @intCast(dy)) * fb.stride;
        var xx: i32 = 0;
        while (xx < 8) : (xx += 1) {
            const dx = x + xx;
            if (dx < 0 or dx >= SCR_W) continue;
            fb.fb[dst_row + @as(usize, @intCast(dx))] = src[@as(usize, @intCast(yy * 8 + xx))];
        }
    }
}

pub fn logo(x: i32, y: i32) void {
    const sn = assets.LOGO_BIN;
    const lw: i32 = assets.LOGO_W;
    const lh: i32 = assets.LOGO_H;
    var yy: i32 = 0;
    while (yy < lh) : (yy += 1) {
        const dy = y + yy;
        if (dy < 0 or dy >= SCR_H) continue;
        const dst_row = @as(usize, @intCast(dy)) * fb.stride;
        var xx: i32 = 0;
        while (xx < lw) : (xx += 1) {
            const dx = x + xx;
            if (dx < 0 or dx >= SCR_W) continue;
            const c = sn[@as(usize, @intCast(yy * lw + xx))];
            if (c != 0) fb.fb[dst_row + @as(usize, @intCast(dx))] = c;
        }
    }
}

// --- text (the ST system font through ZigOS) --------------------------------
pub fn text(msg: []const u8, x: i32, y: i32, fg: u8, bg: u8) void {
    fb.zigos.printText(fb, msg, @intCast(x), @intCast(y), fg, bg);
}

pub fn small(msg: []const u8, x: i32, y: i32, fg: u8, bg: u8) void {
    fb.zigos.printTextSmall(fb, msg, @intCast(x), @intCast(y), fg, bg);
}

pub fn textWidth(msg: []const u8) i32 {
    return @as(i32, @intCast(msg.len)) * 8;
}

pub fn center(msg: []const u8, y: i32, fg: u8, bg: u8) void {
    text(msg, @divTrunc(SCR_W - textWidth(msg), 2), y, fg, bg);
}

pub fn smallCenter(msg: []const u8, y: i32, fg: u8, bg: u8) void {
    small(msg, @divTrunc(SCR_W - @as(i32, @intCast(msg.len)) * 6, 2), y, fg, bg);
}

/// The Go's heading(): the green block, the game's name and a centred title.
pub fn heading(title: []const u8, subtitle: []const u8) void {
    box(12, 6, 10, 10, assets.GREEN);
    text("BUBBLE BOBBLE", 28, 8, assets.GREEN, assets.INK);
    center(title, 26, assets.WHITE, assets.INK);
    if (subtitle.len != 0) center(subtitle, 38, assets.MUTED, assets.INK);
}

/// The Go's banner(): a dark plate with a centred title, drawn over the playfield.
pub fn banner(title: []const u8, subtitle: []const u8, y: i32) void {
    box(PLAY_X + 8, y, PLAY_W - 16, 34, assets.INK);
    box(PLAY_X + 8, y, PLAY_W - 16, 1, assets.YELLOW);
    box(PLAY_X + 8, y + 33, PLAY_W - 16, 1, assets.YELLOW);
    text(title, PLAY_X + @divTrunc(PLAY_W - textWidth(title), 2), y + 5, assets.YELLOW, assets.INK);
    if (subtitle.len != 0) {
        small(subtitle, PLAY_X + @divTrunc(PLAY_W - @as(i32, @intCast(subtitle.len)) * 6, 2), y + 20, assets.WHITE, assets.INK);
    }
}
