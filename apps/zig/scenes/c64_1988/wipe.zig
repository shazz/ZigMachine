// --------------------------------------------------------------------------
// Part 2 ($E200): the screen goes blue from the top, 4 raster lines a frame, for 69 frames.
// A real raster: the border colour ($D020, with $D021) set to blue on line 0 and back to
// black on the line the table gives (stable double IRQ, then the store). The screen is off
// (DEN 0), so the vertical border never opens and covers every sprite.
//
// Where the store lands in its line depends on the sprite DMA still running on it (part 1
// leaves the scrollers' sprites enabled), so on the border lines at the top and bottom the
// switch happens mid-line; the cycles below are VICE's (first loop; the second loop's
// stable raster lands 8 cycles earlier on two of them: ANALYSIS.md).
// --------------------------------------------------------------------------
const vic = @import("vic.zig");
const T = @import("tables.zig");

pub const FRAMES: u8 = 0x46; // the counter ends the part when it reaches 70

pub const Wipe = struct {
    count: u8 = 0, // $E358

    /// Called on the frame part 1 ends, from the main loop (lines 47-48).
    pub fn init(self: *Wipe, q: *vic.Queue) void {
        q.at(47, 19, 0x11, 0x08);
        q.at(47, 25, vic.BANK, 0x03);
        q.at(47, 31, 0x18, 0x18);
        q.at(48, 32, 0x11, 0x08);
        self.count = 0;
    }

    /// One frame; true on the frame the part ends (at line 0, after the blue).
    pub fn frame(self: *Wipe, q: *vic.Queue) bool {
        q.at(0, 30, 0x21, 6);
        q.at(0, 34, 0x20, 6);
        self.count += 1;
        if (self.count == FRAMES) return true;
        const line = T.wipeLine(self.count);
        q.at(1, 45, 0x11, if (line >= 256) 0x88 else 0x08);
        const cyc = blackCycle(self.count);
        q.at(line + 2, cyc - 4, 0x21, 0);
        q.at(line + 2, cyc, 0x20, 0);
        q.at(line + 10, 35, 0x11, 0x08);
        return false;
    }
};

// The cycle of the $D020 store: 10 on lines with no sprite DMA, later where the scrollers'
// sprites are fetched (frames 1-6 and 65-69 of the wipe).
fn blackCycle(k: u8) u16 {
    return switch (k) {
        1 => 39,
        2 => 43,
        3 => 52,
        4 => 43,
        5 => 51,
        6 => 33,
        65 => 39,
        66, 67, 68, 69 => 43,
        else => 10,
    };
}
