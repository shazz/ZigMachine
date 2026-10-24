// --------------------------------------------------------------------------
// NOEXTRA's clock: what the original's code does frame by frame, as pure
// functions of the frame number (no ZigOS import: tests natively).
//
// INTRO ($ABCE..$AC10 in RAM): the D.H.S logo is drawn once at y = t[0]
// ($D586 reads the bob table) and its palette goes in at once ($D51C has no
// VBL wait), then
//   254 frames  held ($E248 with $E244 = 255)
//   255 frames  redrawn at y = the bob table's next value ($E260, $E246 = 256)
//   239 frames  still ($E244 = 240)
//     1 frame   black ($D4B6, no wait either), then the main VBL takes over.
// The intro reads t[0] .. t[33] (read back from Hatari's RAM at the still phase).
//
// MAIN (VBL $AEBE): a word counter ($AF54, 767) is read, then decremented.
// While the value read is >= 1 the screen sits at 0, reading a one-word table
// of 0 — and the common exit ($B10E) stores THAT pointer, one word before the
// bob table, as the bob's read pointer, every frame. So once the count runs
// out the bob reads 0 first, then t[0], t[1] ... (Hatari at main frame 818:
// $AF54 = -52, pointer at t[51], bob $CEE4 = 43 = t[50]). The counter is a
// 16-bit word: 32,768 frames later it reads positive again, the screen rests
// for 32,767 frames and the bob restarts from that 0: kept as is.
// The band's two pointers into the sine table step -3 and +1 words a frame.
// --------------------------------------------------------------------------
const A = @import("assets.zig");

pub const HOLD_FRAMES = 254;
pub const BOUNCE_FRAMES = 255;
pub const STILL_FRAMES = 239;
pub const MAIN_START = HOLD_FRAMES + BOUNCE_FRAMES + STILL_FRAMES + 1; // 749
pub const BOB_WAIT: i16 = 767;

pub const Stage = enum { hold, bounce, still, cut, main };

pub fn stage(f: u32) Stage {
    if (f < HOLD_FRAMES) return .hold;
    if (f < HOLD_FRAMES + BOUNCE_FRAMES) return .bounce;
    if (f < MAIN_START - 1) return .still;
    if (f < MAIN_START) return .cut;
    return .main;
}

/// The intro logo's y in bounce frame n (0-based): the init draw took t[0].
pub fn introY(n: u32) u16 {
    return A.bob[(n + 1) % A.bob.len];
}

/// The band's sine pointers at main frame k, in words (the VBL steps them before Timer B reads).
pub fn bandPhase(k: u32) struct { p1: u32, p2: u32 } {
    return .{ .p1 = 252 - 3 * (k % 84), .p2 = k % 252 };
}

/// Band row r's first ramp entry (words): the two sine reads are byte offsets.
pub fn bandOffset(p1: u32, p2: u32, r: u32) u8 {
    const s1 = A.sine[(p1 + r) % A.sine.len];
    const s2 = A.sine[(p2 + 2 * r) % A.sine.len];
    return @intCast((s1 + s2) / 2);
}

/// The bob, as the main VBL runs it: counter value read, then decremented.
pub const Bob = struct {
    count: i16 = BOB_WAIT,
    next: u8 = BEFORE, // BEFORE: the zero word ahead of the table

    const BEFORE: u8 = 0xFF;

    pub fn step(self: *Bob) u16 {
        const was = self.count;
        self.count -%= 1;
        if (was >= 1) {
            self.next = BEFORE;
            return 0;
        }
        const v = if (self.next == BEFORE) 0 else A.bob[self.next];
        self.next = if (self.next == BEFORE or self.next + 1 == A.bob.len) 0 else self.next + 1;
        return v;
    }
};

// --- the scroller ($D15C) --------------------------------------------------
// The text is a strip of 8-px bytes, 4 to a 32-px glyph. Call f (one a frame)
// adds the column ending at byte f to one of two 20-column rings and draws
// that ring, so the screen's 20 16-px columns show bytes f-39 .. f, column c
// holding bytes f-39+2c and f-38+2c: 8 px a frame. The first char is text[1]
// (the pointer is bumped before it is read), and a zero wraps it to text[0].

/// The original's lookup ($D106): char -> glyph, 0 ('A') for a char the charset lacks.
const GLYPH = blk: {
    var t = [_]u8{0} ** 256;
    for (A.charset, 0..) |k, i| t[k] = i;
    break :blk t;
};

/// Glyph index of strip char n (n >= 0).
pub fn glyphOf(n: u32) u8 {
    return GLYPH[A.text[(n + 1) % A.text.len]];
}

/// Byte `b` of the strip, glyph row `y` (0..15): 8 pixels, MSB leftmost. Blank before the start.
pub fn stripByte(b: i32, y: u32) u8 {
    if (b < 0) return 0;
    const ub: u32 = @intCast(b);
    const g: u32 = glyphOf(ub >> 2);
    const q = ub & 3;
    return A.font[g * 64 + (q >> 1) * 32 + 2 * y + (q & 1)];
}

/// Column c's top line in the 160-stride screen at call f: line 50 + the wave (lines * 160).
pub fn columnLine(f: u32, c: u32) u32 {
    return 50 + A.wave[((f + 1) % 180) + c] / 160;
}

test "noextra timeline: the intro ends where the main bob starts" {
    const std = @import("std");
    try std.testing.expectEqual(@as(u32, 749), MAIN_START);
    try std.testing.expectEqual(Stage.main, stage(MAIN_START));
    try std.testing.expectEqual(Stage.cut, stage(MAIN_START - 1));
    try std.testing.expectEqual(@as(u16, 58), introY(BOUNCE_FRAMES - 1)); // Hatari, still phase
    var b = Bob{};
    for (0..768) |_| try std.testing.expectEqual(@as(u16, 0), b.step());
    for (768..818) |_| _ = b.step();
    try std.testing.expectEqual(@as(u16, 43), b.step()); // Hatari: main frame 818, $CEE4 = 43
}

test "noextra timeline: band pointers and offsets stay inside the ramp" {
    const std = @import("std");
    try std.testing.expectEqual(@as(u32, 252), bandPhase(0).p1);
    try std.testing.expectEqual(@as(u32, 3), bandPhase(83).p1);
    try std.testing.expectEqual(@as(u32, 252), bandPhase(84).p1);
    for (0..252) |k| for (0..146) |r| {
        const ph = bandPhase(@intCast(k));
        try std.testing.expect(bandOffset(ph.p1, ph.p2, @intCast(r)) + 37 <= A.ramp.len);
    };
}

test "noextra timeline: the strip starts on text[1] and the wave stays in the band" {
    const std = @import("std");
    try std.testing.expectEqual(@as(u8, 0), stripByte(-1, 0));
    try std.testing.expectEqual(glyphOf(0), glyphOf(@intCast(A.text.len))); // wrap
    for (0..180) |f| for (0..20) |c| {
        const y = columnLine(@intCast(f), @intCast(c));
        try std.testing.expect(y >= 78 + 4 and y + 20 <= 224);
    };
}
