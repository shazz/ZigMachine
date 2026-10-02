// F2's scroller ($5B7C): FONTE.DAT's 32x27 glyphs in two one-plane buffers of
// 27 lines x 40 bytes ($54800 / $54D00), used on alternate VBLs. Each VBL the
// buffer in hand is moved left two bytes (a line takes the next line's first
// two bytes with it), its last two bytes get a byte-wide slice of the glyph,
// and it is copied to plane 0 of lines 201..227 -- in the lower border -- of
// the screen being drawn. A glyph goes in as [0 b0] [b0 b1] [b1 b2] [b2 b3]
// [b3 0], one pair a VBL ($5D50 .. $62B0), and the last one runs on into the
// fetch of the next character ($63FC): 40 pixels a character. Two buffers 8
// pixels apart, each moving 16 a turn: 8 pixels a VBL. The very first VBL,
// and the one after the text's $FF, only fetch, and write nothing: that
// buffer's last two bytes keep what moved in from the line below.
const std = @import("std");
const ram = @import("ram.zig");
const A = @import("../assets.zig");

const TEXT = A.HADES.TEXT;
pub const TOP = 201; // $7DA0 / 160
const LINES = 27;
const LINE = 40;
const GLYPH = 108;

pub const Scroll = struct {
    bufs: [2][LINES * LINE + 2]u8, // + the two bytes the last line reads
    cur: u1, // which one $78F4 names
    step: u8, // $7904: 0 = fetch, 1..5 = a slice
    glyph: usize, // $7908, into FONTE
    next: usize, // $7900, into TEXT

    pub fn enter(self: *Scroll) void {
        for (&self.bufs) |*b| @memset(b, 0); // $7740
        self.cur = 0;
        self.step = 0; // $7730
        self.glyph = 0;
        self.next = 0;
    }

    pub fn vbl(self: *Scroll, s: *ram.Screen) void {
        const b = &self.bufs[self.cur];
        for (0..LINES) |l| std.mem.copyForwards(u8, b[l * LINE ..][0..LINE], b[l * LINE + 2 ..][0..LINE]);
        if (self.step == 0) self.fetch() else self.slice(b);
        for (0..LINES) |l| {
            for (0..20) |w| {
                const at = (TOP + l) * ram.LINE + w * 8;
                s[at] = b[l * LINE + 2 * w];
                s[at + 1] = b[l * LINE + 2 * w + 1];
            }
        }
        self.cur ^= 1;
    }

    /// $63FC: the next character; on the text's $FF, back to its start (and
    /// this routine again next VBL).
    fn fetch(self: *Scroll) void {
        if (self.next >= TEXT.len) {
            self.next = 0;
            self.step = 0;
            return;
        }
        self.glyph = @as(usize, TEXT[self.next]) * GLYPH;
        self.next += 1;
        self.step = 1;
    }

    /// $5D50 .. $62B0: bytes 38 and 39 of every line from the glyph.
    fn slice(self: *Scroll, b: *[LINES * LINE + 2]u8) void {
        const k = self.step - 1; // 0..4
        for (0..LINES) |l| {
            const g = A.FONTE[self.glyph + l * 4 ..][0..4];
            b[l * LINE + 38] = if (k == 0) 0 else g[k - 1];
            b[l * LINE + 39] = if (k == 4) 0 else g[k];
        }
        if (k == 4) self.fetch() else self.step += 1; // $62B0 runs on into $63FC
    }
};

comptime {
    @setEvalBranchQuota(10000);
    for (TEXT) |c| if (c >= A.FONTE_GLYPHS) @compileError("F2's text names a glyph FONTE.DAT has not");
}

test "a glyph goes in as [0 b0] [b0 b1] [b1 b2] [b2 b3] [b3 0] after a fetch" {
    const s = std.testing;
    var sc: Scroll = undefined;
    sc.enter();
    var scr: ram.Screen = undefined;
    @memset(&scr, 0);
    const g = A.FONTE[@as(usize, TEXT[0]) * GLYPH ..][0..4];
    sc.vbl(&scr); // the fetch, into buffer 0
    const want = [5][2]u8{ .{ 0, g[0] }, .{ g[0], g[1] }, .{ g[1], g[2] }, .{ g[2], g[3] }, .{ g[3], 0 } };
    for (want) |w| {
        const b = sc.cur; // the buffer this VBL uses
        sc.vbl(&scr);
        try s.expectEqualSlices(u8, &w, sc.bufs[b][38..40]);
        // copied to plane 0 of line 201, its last group
        try s.expectEqualSlices(u8, &w, scr[TOP * ram.LINE + 19 * 8 ..][0..2]);
    }
    try s.expectEqual(@as(u8, 1), sc.step); // the last slice fetched the next
}
