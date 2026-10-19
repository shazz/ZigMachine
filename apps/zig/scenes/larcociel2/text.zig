// --------------------------------------------------------------------------
// The scrolling text -- democonstructionkit's scrolling.SliceStream feeding
// scrolling.New's 36-slot GlyphWindow, transcribed from the Go's
// internal/demo/game.go.
//
// Every 50 Hz tick the stream shifts one 8-pixel slice into a 36-slot ring.
// Each message character is a SliceToken of Width 32, so it owns exactly four
// slices (width 32 / slice 8); a glyph is 32 wide in the atlas. The window
// samples slot i at ring position (head+i), and the window itself is 36 slots
// eight pixels apart at x = 16 + 8i -- the whole screen width.
//
// `font.bin` holds the atlas as 1-bit alpha; there is no colour here, because
// the Go's text shader rule reads the glyph's alpha only (i = i%8 + 8).
// --------------------------------------------------------------------------
const std = @import("std");
const assets = @import("assets.zig");

pub const CAP = 36;

pub const Slice = struct {
    /// Atlas glyph 0..30, or -1 for an empty slot (the stream's Initial).
    glyph: i8 = -1,
    /// Which of the glyph's four 8-pixel columns.
    index: u8 = 0,
};

pub const Stream = struct {
    slices: [CAP]Slice = [_]Slice{.{}} ** CAP,
    head: usize = 0,
    token: usize = 0,
    index: usize = 0,
    /// The message, pre-decoded to atlas glyph indices at init.
    tokens: [assets.message.len]u8 = undefined,

    fn glyphIndex(c: u8) u8 {
        return if (std.mem.indexOfScalar(u8, assets.font_order, c)) |i| @intCast(i) else 30;
    }

    pub fn init(self: *Stream) void {
        for (assets.message, 0..) |c, i| self.tokens[i] = glyphIndex(c);
        self.head = 0;
        self.token = 0;
        self.index = 0;
        self.slices = [_]Slice{.{}} ** CAP;
    }

    pub fn step(self: *Stream) void {
        self.head = (self.head + 1) % CAP;
        const tail = (self.head + CAP - 1) % CAP;
        self.slices[tail] = .{ .glyph = @intCast(self.tokens[self.token]), .index = @intCast(self.index) };
        self.index += 1;
        if (self.index >= 4) {
            self.index = 0;
            self.token = (self.token + 1) % self.tokens.len;
        }
    }

    /// The slice shown in window slot `i` (0 = leftmost, 35 = rightmost).
    pub fn slot(self: *const Stream, i: usize) Slice {
        return self.slices[(self.head + i) % CAP];
    }
};
