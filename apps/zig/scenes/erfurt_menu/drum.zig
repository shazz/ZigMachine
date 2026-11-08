// --------------------------------------------------------------------------
// The drum's picture: a texture of 12 faces x 24 lines, 256 px wide, one bit a
// pixel, wrapped round a cylinder by two tables per radius.
//
// GEOMETRY ($109FC, at init). For a half-cylinder of radius r (30..50) and a
// line t = -r..r from its middle, profile index 45 + t*45/r picks, from two
// 91-word tables in the menu ($31022 front, $310D8 back), how many texture
// lines down from the drum's angle that screen line shows. The back face is
// switched off for t = -9..7 (the front hides it there). The drum is an upper
// half of radius r_a over a lower half of radius r_b ($1215A).
//
// FACES ($116DE, $117B0). The texture holds 12 faces, the drum 16 entries: the
// face of angle-line p is p/24, its slot p/24 mod 12 and its entry p/24 mod 16.
// A slot is redrawn when the entry it should hold changes; that only happens
// on the hidden side, so drawing it at once (the original spreads it over
// frames) shows the same picture.
//
// DRAW ($11D38): screen line drum_top + i, clipped to lines 45..166, gets the
// front texture line in plane 0 and the back one in plane 1, 192 px at x 64.
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const M = @import("motion.zig");
const S = @import("screen.zig");

pub const SLOTS = 12; // $40ED0
pub const TEX_LINES = SLOTS * 24; // $4CD08 = 288
const CLIP_TOP: i32 = 45; // $2D
const CLIP_BOT: i32 = 166; // $4EBCC
const MAX_LINES = 101; // 2 * 50 + 1

pub const Item = struct { flags: u8, text: []const u8 };

/// The 16 entries as the menu builds them at $10B2A from the loader's directory
/// and the strings at $1F988 (read off the running menu). '@' is the font's
/// small "STE" tag. Flags: bit 5 = a separator, not selectable; bit 7 = STE only.
pub const items = [16]Item{
    .{ .flags = 0x20, .text = "--- DISK 1 ---" },
    .{ .flags = 0x01, .text = "CHECKERBOARD" },
    .{ .flags = 0x01, .text = "BB 2K27 INVITRO" },
    .{ .flags = 0x01, .text = "VECTRONIX" },
    .{ .flags = 0x01, .text = "PARTY SCROLLER" },
    .{ .flags = 0x01, .text = "INIT SEQUENCE" },
    .{ .flags = 0x01, .text = "DUUBSCROLL" },
    .{ .flags = 0x01, .text = "REALTIME READER" },
    .{ .flags = 0x01, .text = "HIGHSCORES" },
    .{ .flags = 0x20, .text = "--- DISK 2 ---" },
    .{ .flags = 0x01, .text = "SHADOW OF ERFURT" },
    .{ .flags = 0x81, .text = "ERFURT PLUMBER @" },
    .{ .flags = 0x81, .text = "CARRBEERS @" },
    .{ .flags = 0x81, .text = "NOODLE SOUP @" },
    .{ .flags = 0x81, .text = "NIGHTSHIFT @" },
    .{ .flags = 0x81, .text = "RASTERBARS @" },
};
/// $844A8's 17th record: the part ERFURT26 opens.
pub const hidden_title = "WHAT? YOU FOUND IT!";

pub fn selectable(item: i32) bool {
    return items[@intCast(item)].flags & 0x20 == 0;
}

pub const Drum = struct {
    tex: [TEX_LINES][16]u16,
    slot_item: [SLOTS]i8,
    front: [MAX_LINES]i16, // texture lines below the angle, per drum line
    back: [MAX_LINES]i16, // -1: the back face is not drawn on that line
    n: usize,
    r_a: i16,
    r_b: i16,

    pub fn init(self: *Drum) void {
        for (&self.tex) |*l| @memset(l, 0);
        @memset(&self.slot_item, -1);
        self.r_a = 0;
        self.r_b = 0;
        self.n = 0;
    }

    /// $1215A: the profile of an upper half r_a over a lower half r_b.
    pub fn setShape(self: *Drum, r_a: i16, r_b: i16) void {
        if (r_a == self.r_a and r_b == self.r_b) return;
        self.r_a = r_a;
        self.r_b = r_b;
        const ra: i32 = r_a;
        const rb: i32 = r_b;
        self.n = @intCast(ra + rb + 1);
        for (0..self.n) |i| {
            const t: i32 = @as(i32, @intCast(i)) - ra;
            const r = if (t <= 0) ra else rb;
            const idx: usize = @intCast(@divTrunc(t * 45, r) + 45);
            self.front[i] = @intCast(A.be(A.profile, idx) >> 5);
            const hidden = t >= -9 and t <= 7;
            self.back[i] = if (hidden) -1 else @intCast(A.be(A.profile, 91 + idx) >> 5);
        }
    }

    /// $116DE: make every slot hold the entry its face shows from `line`.
    pub fn faces(self: *Drum, line: i32) void {
        const first = @divTrunc(line, M.FACE);
        const lo = @mod(first, SLOTS);
        for (0..SLOTS) |s| {
            const ahead = @mod(@as(i32, @intCast(s)) - lo, SLOTS);
            const it: i8 = @intCast(@mod(@mod(first, M.ITEMS) + ahead, M.ITEMS));
            if (self.slot_item[s] == it) continue;
            self.slot_item[s] = it;
            self.paint(s, items[@intCast(it)].text);
        }
    }

    /// $118D8: the entry's text, centred in 256 px, 4 lines down its slot.
    fn paint(self: *Drum, slot: usize, text: []const u8) void {
        const base = slot * 24;
        for (self.tex[base..][0..24]) |*l| @memset(l, 0);
        var x: usize = (256 - @min(text.len * 12, 256)) / 2;
        for (text) |ch| {
            if (ch < 0x20 or ch - 0x20 >= A.DRUM_GLYPHS) {
                x += 12;
                continue;
            }
            const g = @as(usize, ch - 0x20) * 16;
            for (0..16) |r| {
                const w = A.be(A.drumfont, g + r);
                if (w == 0) continue;
                const row = &self.tex[base + 4 + r];
                const bits = (@as(u32, w) << 16) >> @intCast(x & 15);
                const k = x >> 4;
                row[k] |= @truncate(bits >> 16);
                if (k + 1 < 16) row[k + 1] |= @truncate(bits);
            }
            x += 12;
        }
    }

    /// $11D38: every drum line of this frame into planes 0 and 1.
    pub fn draw(self: *const Drum, st: *S.Screen, top: i32, line: i32) void {
        const rot = @mod(line, TEX_LINES);
        var y: i32 = CLIP_TOP;
        while (y <= CLIP_BOT) : (y += 1) {
            const row = &st.rows[@intCast(y)];
            const i = y - top;
            if (i < 0 or i >= @as(i32, @intCast(self.n))) {
                for (4..16) |g| {
                    row[4 * g] = 0;
                    row[4 * g + 1] = 0;
                }
                continue;
            }
            const k: usize = @intCast(i);
            const f = &self.tex[@intCast(@mod(rot + self.front[k], TEX_LINES))];
            const b = self.back[k];
            const bl: ?*const [16]u16 = if (b < 0) null else &self.tex[@intCast(@mod(rot + b, TEX_LINES))];
            for (0..12) |j| {
                row[4 * (4 + j)] = f[2 + j];
                row[4 * (4 + j) + 1] = if (bl) |l| l[2 + j] else 0;
            }
        }
    }
};
