// --------------------------------------------------------------------------
// Colour bank: RGB colours to palette entries, allocated afresh every frame.
//
// A canvas port that blends (a smoothed scroller, chrome_draw.zig) produces
// more colours over its run than a palette holds, but few in any one frame.
// So the frame asks the bank for each colour it draws: the first request takes
// the next free entry from `first` up and writes the colour into the palette,
// later requests get the same entry. begin() forgets the previous frame.
//
// Open addressing over 512 slots, stamped with the frame number so begin() does
// not clear the table. No ZigOS import: tests natively (colour_bank_test.zig).
// --------------------------------------------------------------------------
const std = @import("std");

const SLOTS = 512; // at most 255 colours: the table never fills past half
const MASK = SLOTS - 1;

pub const ColourBank = struct {
    first: u16,
    next: u16,
    frame: u16,
    keys: [SLOTS]u32,
    vals: [SLOTS]u8,
    stamps: [SLOTS]u16,

    /// Entries `first`..255 are the bank's.
    pub fn init(self: *ColourBank, first: u8) void {
        self.first = first;
        self.next = first;
        self.frame = 0;
        @memset(&self.stamps, 0);
        @memset(&self.keys, 0);
        @memset(&self.vals, 0);
    }

    /// A new frame: every entry is free again.
    pub fn begin(self: *ColourBank) void {
        self.frame +%= 1;
        if (self.frame == 0) { // stamps wrapped: clear them once
            @memset(&self.stamps, 0);
            self.frame = 1;
        }
        self.next = self.first;
    }

    /// Entries handed out this frame.
    pub fn used(self: *const ColourBank) usize {
        return self.next - self.first;
    }

    /// The entry showing `rgb` (0x00BBGGRR) this frame, written into `palette` as
    /// an opaque colour when it is new. Null when the bank's entries are all taken.
    pub fn entry(self: *ColourBank, palette: [*]u32, rgb: u32) ?u8 {
        var slot: usize = (rgb *% 0x9E3779B1) >> 23;
        while (self.stamps[slot] == self.frame) : (slot = (slot + 1) & MASK) {
            if (self.keys[slot] == rgb) return self.vals[slot];
        }
        if (self.next > 255) return null;
        const e: u8 = @intCast(self.next);
        self.next += 1;
        self.stamps[slot] = self.frame;
        self.keys[slot] = rgb;
        self.vals[slot] = e;
        palette[e] = 0xFF00_0000 | rgb;
        return e;
    }
};
