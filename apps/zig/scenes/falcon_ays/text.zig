// --------------------------------------------------------------------------
// The red texts (8xx 1D, 1E, 2B, 2C, 32; Falcon timer $656C, mains $6404..$6524): mode 804.
// A 19-character line in a 16x32, 8-bit font (intensity 0..$72, the grain drawn into the
// glyphs) is copied into a 320x42 byte buffer at row 4, x 8. Once the part's tick counter
// reaches its threshold (160 ticks for the first two texts, 20 for the others) the buffer is
// blurred IN PLACE every frame: p = (UL + UR + DL + DR) >> 2, the four diagonal neighbours.
// In place, it smears toward one side; the truncation darkens it until the text is gone. The
// buffer goes through a 128-entry palette (black -> red -> white) onto 40 screen lines.
// Here the blur runs once per 50 Hz tick, so the dissolve keeps the original's speed at 60 Hz.
//
// The font and palette are the original's with the local rip (art.zig); otherwise the system
// font, scaled to 16x32 with a fixed grain, and a generated ramp stand in.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const arena = @import("arena.zig");
const art = @import("art.zig");

const BW = 320;
const BH = 42;
const BLUR_FROM = BW + 1; // row 1, column 1
const BLUR_LEN = 10140; // bytes, as $691E
const GW = 16;
const GH = 32;

pub const Line = struct { text: *const [19]u8, row: u8, threshold: u16 };

// 81D, 81E, 82B, 82C, 832 (DATA $F38EC.., 20 bytes apart; rows from screen offsets $C800/$DC00/$D200).
pub const LINES = [5]Line{
    .{ .text = "IN AUTUMN 2003.....", .row = 80, .threshold = 160 },
    .{ .text = ".......WE ARE BACK!", .row = 88, .threshold = 160 },
    .{ .text = "      PRESENTS     ", .row = 84, .threshold = 20 },
    .{ .text = "SOME RANDOM STUFF..", .row = 84, .threshold = 20 },
    .{ .text = "...FOR CHOSNECK MAG", .row = 84, .threshold = 20 },
};

var buf: *[BW * BH]u8 = undefined;
var pal: [128]u16 = undefined;
var font: *[59 * GW * GH]u8 = undefined; // ' '..'Z'

pub fn init(sys_font: []const u8) void {
    buf = arena.take([BW * BH]u8);
    font = arena.take([59 * GW * GH]u8);
    for (0..128) |i| pal[i] = if (art.text_pal.len == 256) art.be16(art.text_pal, i * 2) else genPal(i);
    if (art.text_font.len == font.len) @memcpy(font, art.text_font) else genFont(sys_font);
}

pub const Text = struct {
    line: Line = LINES[0],
    ticks: u16 = 0,

    pub fn start(v: u8) Text {
        const i: usize = switch (v) {
            0x1D => 0,
            0x1E => 1,
            0x2B => 2,
            0x2C => 3,
            else => 4,
        };
        const t = Text{ .line = LINES[i] };
        @memset(buf, 0);
        for (t.line.text, 0..) |ch, k| glyph(ch, 8 + k * GW);
        blur();
        return t;
    }

    /// The timer slot: count ticks (capped at 1000); past the threshold, one blur a tick.
    /// The timer slot (100 Hz): count ticks, capped at 1000.
    pub fn count(self: *Text) void {
        if (self.ticks < 1000) self.ticks += 1;
    }

    /// A frame (the main slot): past the threshold, one in-place blur.
    pub fn blurFrame(self: *const Text) void {
        if (self.ticks >= self.line.threshold) blur();
    }

    /// The band through the palette; the rest of the screen is what 807 or 814 left there.
    pub fn draw(self: *const Text, fb: zg.tc.Fb) void {
        for (0..40) |y| {
            const src = buf[y * BW ..][0..BW];
            const dst = fb.row(self.line.row + y);
            for (dst, src) |*d, s| d.* = pal[s & 127];
        }
    }
};

fn glyph(ch: u8, x: usize) void {
    const c: usize = if (ch >= ' ' and ch <= 'Z') ch - ' ' else 0;
    const g = font[c * GW * GH ..][0 .. GW * GH];
    for (0..GH) |y| @memcpy(buf[(4 + y) * BW + x ..][0..GW], g[y * GW ..][0..GW]);
}

// $691E: the in-place diagonal blur, in the original's order (it smears toward the start).
fn blur() void {
    var i: usize = BLUR_FROM;
    while (i < BLUR_FROM + BLUR_LEN) : (i += 1) {
        const s = @as(u16, buf[i - BW - 1]) + buf[i - BW + 1] + buf[i + BW - 1] + buf[i + BW + 1];
        buf[i] = @intCast(s >> 2);
    }
}

// --- stand-ins ---

// black -> red -> white over the 128 entries (the original's ramp is $F37EC).
fn genPal(i: usize) u16 {
    const t: u32 = @intCast(i);
    const r: u32 = @min(255, t * 255 / 48);
    const g: u32 = if (t < 48) t * 40 / 48 else @min(255, 40 + (t - 48) * 215 / 80);
    const b: u32 = if (t < 64) t * 24 / 64 else @min(255, 24 + (t - 64) * 231 / 64);
    return zg.tc.rgb565(@intCast(r), @intCast(g), @intCast(b));
}

// The 8x8 system font scaled 2x4 to 16x32, ink at $60 with a fixed grain (a hash per pixel).
fn genFont(sys: []const u8) void {
    for (0..59) |c| for (0..GH) |y| for (0..GW) |x| {
        const code = c + ' ';
        const lit = sys.len >= (code + 1) * 64 and sys[code * 64 + (y / 4) * 8 + x / 2] != 0;
        const h: u32 = @truncate((c * 977 + y * 131 + x * 31) *% 2654435761 >> 13);
        font[(c * GH + y) * GW + x] = if (lit) @intCast(0x48 + h % 0x2B) else 0;
    };
}

test "the blur is a mean of the four diagonals and keeps values under 128" {
    @memset(buf, 0);
    buf[2 * BW + 2] = 100;
    blur();
    try std.testing.expectEqual(@as(u8, 25), buf[BW + 1]);
    for (buf) |v| try std.testing.expect(v < 128);
}
