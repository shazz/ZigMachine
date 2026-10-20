// --------------------------------------------------------------------------
// Metallinos' bottom scroller ($dca6).  Eight rows of `roxl.w` across the 20
// words of a line, fed one bit a frame out of the pending character -- one
// pixel a frame, a new character every eight.  The panel sits on rows 191..198
// (screen + $7760 + 4, plane 2), so it shares its colour with the credits font
// and the Timer-B chain gives it its own value below the last split.
//
// The shift runs across all 26 words of P.small, the window's 20 and three
// either side, so ZIG MODE can show it through the open side borders.  Bits
// enter at buffer px 415 now, not the window's last pixel (buffer px 367), so
// init() runs AHEAD_PX frames' worth of shifting up front: the window then
// sees every bit on the frame the ST did.
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const P = @import("planes.zig");

const CHAR_FRAMES: u16 = 8;
const FIRST_CHAR: u8 = 0x20;
const AHEAD_PX: usize = (P.BUF_WORDS - P.WIN_WORD - P.WORDS) * 16; // 48 = 6 characters

pub const Small = struct {
    pending: [P.SMALL_ROWS]u16, // $25cdc, the character still shifting in
    count: u16, // $259da
    text: usize, // $26348

    pub fn init(self: *Small) void {
        self.pending = .{0} ** P.SMALL_ROWS;
        self.count = CHAR_FRAMES;
        self.text = 0;
        for (P.small) |*row| @memset(row, 0);
        for (0..AHEAD_PX) |_| self.update();
    }

    /// $328e: take the next byte, wrap at the end of the text.  The font starts
    /// at ' ' and holds 96 cells; anything outside that shifts in blank (the
    /// subtract used to wrap into a huge index and overflow the multiply).
    fn nextChar(self: *Small) void {
        const ch = A.scroll_small[self.text];
        self.text += 1;
        if (self.text >= A.scroll_small.len) self.text = 0;
        self.count = 0;
        const cell: ?usize = if (ch >= FIRST_CHAR and ch - FIRST_CHAR < A.smallfont.len / 8)
            (@as(usize, ch) - FIRST_CHAR) * 8
        else
            null;
        for (&self.pending, 0..) |*w, r| {
            w.* = if (cell) |c| @as(u16, A.smallfont[c + r]) << 8 else 0;
        }
    }

    pub fn update(self: *Small) void {
        if (self.count >= CHAR_FRAMES) self.nextChar();
        self.count += 1;
        for (&self.pending, 0..) |*p, r| {
            var carry: u16 = p.* >> 15;
            p.* <<= 1;
            var k: usize = P.BUF_WORDS;
            while (k > 0) {
                k -= 1;
                const w = P.small[r][k];
                P.small[r][k] = (w << 1) | carry;
                carry = w >> 15;
            }
        }
    }
};
