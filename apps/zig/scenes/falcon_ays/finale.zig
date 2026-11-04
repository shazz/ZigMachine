// --------------------------------------------------------------------------
// The end of the show, around the ball-oid (balloid.zig):
//   839/83A $7E3E  "thanks for watching!" / "now go read the mag!": a 160x16 strip of 17 levels
//                  (127 = the white background) through a 256-entry ramp (black -> brown ->
//                  salmon -> white from 128) at lines 92..99. The timer ($822C) holds 300
//                  ticks, then adds 2 to the ramp offset a tick until $100: the text fades into
//                  the white.
//   82A/83B/83C $7C28  the greetings: a pre-rendered 1000x8 strip; 320 pixels of it a frame, in
//                  24-pixel chunks whose rows step down 0,1,2,2,3,3,3,3,3,4,4,5,6,7 across the
//                  screen (a slanted baseline from line 120); the start walks a 1024-entry
//                  table of byte offsets (4..1356), one entry a frame, back and forth.
//   83E $72A0      the end: the whole screen fed back through a two-pixel average every frame,
//                  until the last ball frame has smeared away.
// With the local rip the strips, the ramp and the offsets are the original's; otherwise the
// system font and generated ramps stand in.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const arena = @import("arena.zig");
const art = @import("art.zig");
const accents = @import("accents.zig");
const tc = zg.tc;

const W = 320;
const GW = 1000; // greetings strip width
const STEPS = [14]u8{ 0, 1, 2, 2, 3, 3, 3, 3, 3, 4, 4, 5, 6, 7 };
const GREETS = "theblacklotus satantronic avena phf evolution sectorone exocet cruor paranoia aliveteam mjjprod lineout escape dhs tscc cream checkpoint mysticbytes ephidrena newbeat ymrockers kua dune stknights trollaco paradize";

var thanks: *[2][W * 8]u8 = undefined;
var ramp: [256]u16 = undefined;
var greets: *[GW * 8]u16 = undefined;
var offsets: [1024]u16 = undefined;

pub fn init(font: []const u8) void {
    thanks = arena.take([2][W * 8]u8);
    greets = arena.take([GW * 8]u16);
    if (art.thanks.len == 2 * W * 8) {
        for (0..2) |k| @memcpy(&thanks[k], art.thanks[k * W * 8 ..][0 .. W * 8]);
    } else {
        textStrip(&thanks[0], font, "thanks for watching!");
        textStrip(&thanks[1], font, "now go read the mag!");
    }
    for (0..256) |i| ramp[i] = if (art.thanks_ramp.len == 512) art.be16(art.thanks_ramp, i * 2) else genRamp(i);
    if (art.greets.len == GW * 8 * 2) {
        for (0..GW * 8) |i| greets[i] = art.be16(art.greets, i * 2);
    } else genGreets(font);
    for (0..1024) |i| {
        if (art.greets_path.len == 2048) {
            offsets[i] = art.be16(art.greets_path, i * 2);
        } else {
            const s = zg.fixtrig.sin(@as(u32, @intCast(i)) << 22);
            offsets[i] = @intCast((680 + @divFloor(s * 676, zg.fixtrig.ONE)) & ~@as(i32, 1));
        }
    }
}

/// 839 / 83A: which line, and the fade.
pub const Thanks = struct {
    which: u1 = 0,
    ticks: u16 = 0,
    offset: u16 = 0,

    /// The timer slot ($822C, 100 Hz): hold 300 calls (3 s), then 2 bytes of ramp a call.
    pub fn tick(self: *Thanks) void {
        self.ticks +|= 1;
        if (self.ticks > 300 and self.offset < 0x100) self.offset += 2;
    }

    pub fn draw(self: *const Thanks, fb: tc.Fb) void {
        // Each strip is 160x16 (2,560 bytes), drawn at the left from line 92.
        const s = &thanks[self.which];
        for (0..TH) |y| {
            const row = fb.pixels + (92 + y) * fb.stride;
            for (0..TW) |x| row[x] = ramp[@min(255, @as(usize, s[y * TW + x]) + self.offset / 2)];
        }
    }
};

/// The greetings line at its frame's offset (an entry a frame).
pub fn drawGreets(fb: tc.Fb, frame: u32) void {
    const start: usize = offsets[(frame) % 1024] / 2; // byte offset -> pixel
    for (STEPS, 0..) |dy, c| {
        const x0 = c * 24;
        if (x0 >= W) break;
        const n: usize = @min(24, W - x0);
        for (0..8) |y| {
            const dst = fb.pixels + (120 + dy + y) * fb.stride + x0;
            const src = greets[y * GW + @min(GW - n, start + x0) ..][0..n];
            @memcpy(dst[0..n], src);
        }
    }
}

/// 83E: the shown frame, each pixel averaged with its right neighbour, into the back buffer.
pub fn melt(dst: tc.Fb, src: tc.Fb) void {
    accents.average(dst, src, 0, 200);
}

// --- stand-ins ---

fn glyphBit(font: []const u8, ch: u8, x: usize, y: usize) bool {
    return font.len >= (@as(usize, ch) + 1) * 64 and font[@as(usize, ch) * 64 + y * 8 + x] != 0;
}

// The text in the system font, ink 0 on the white 127, left-aligned like the original.
fn textStrip(s: *[W * 8]u8, font: []const u8, t: []const u8) void {
    @memset(s, 127);
    for (t, 0..) |ch, k| for (0..8) |y| for (0..8) |x| {
        if (glyphBit(font, ch, x, y)) s[(4 + y) * TW + 6 + k * 7 + x] = 0;
    };
}

const TW = 160; // a thanks strip: 160x16 bytes
const TH = 16;

// black -> dark red-brown -> salmon -> white at 128 and over.
fn genRamp(i: usize) u16 {
    if (i >= 128) return 0xFFFF;
    const t: u32 = @intCast(i);
    return tc.rgb565(@intCast(@min(255, t * 2 + t / 2)), @intCast(t * 2), @intCast(t * 2));
}

fn genGreets(font: []const u8) void {
    const ink = tc.rgb565(255, 220, 220);
    @memset(greets, 0);
    for (GREETS, 0..) |ch, k| for (0..8) |y| for (0..6) |x| {
        if (k * 6 + 2 + x >= GW) continue;
        if (glyphBit(font, ch, x, y)) greets[y * GW + k * 6 + 2 + x] = ink;
    };
}
