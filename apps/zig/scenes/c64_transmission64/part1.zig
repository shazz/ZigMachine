// --------------------------------------------------------------------------
// Part 1 ($2800, IRQ $2B7B on line 248): rings of dither characters ripple out over the
// screen you typed RUN on.
//
// 24 rings ($10-$27 in zero page, $10 the centre) hold a character code each, 0 for "none".
// Every frame the generated routine at $2C80 visits the rings from the outermost ($27) in,
// and for each ring either writes its code (light blue) into every cell of the ring, or, when
// the ring is 0, puts back the cells of the boot screen saved at $7400/$7800. It takes almost
// a whole frame (line 260 to line ~216 of the next), so it races the beam: a cell shows its
// new code this frame only if it was stored before its row's bad line (vic.zig times it).
// Every third frame $2C00 moves every ring's code one ring out and feeds the centre the next
// of 242 codes ($7C00); after the last, the part ends ($0F set: the IRQ hands over to $0986
// and releases the main loop).
// --------------------------------------------------------------------------
const vic = @import("vic.zig");
const Clock = @import("clock.zig").Clock;
const data = @import("data.zig");

pub const RINGS = 24;
pub const FEED = 0xF2; // codes fed to the centre ($2C6F stops at $F2)
const INK: u8 = 0x0E; // light blue: the routine's LDY #$0E

pub const Part1 = struct {
    ring: [RINGS]u8 = .{0} ** RINGS, // $10..$27
    wait: u8 = 3, // $2C09: frames to the next step
    fed: u8 = 0, // $2C6F: next feed index
    done: bool = false, // $0F

    /// $2C80, starting at `start` (after the IRQ's music call): the stores, timed. Returns
    /// the clock at its RTS.
    pub fn draw(self: *const Part1, start: Clock, st: *vic.Stores, d: data.Part1) Clock {
        var c = start;
        c.rd(2); // LDY #$0E
        var k: usize = RINGS;
        while (k > 0) {
            k -= 1;
            const cells = d.ring(RINGS - 1 - k); // the code's order: $27 first
            c.rd(3); // LDX ring
            const code = self.ring[k];
            if (code != 0) {
                c.rd(3); // BNE taken
                for (0..cells.len / 2) |i| {
                    const cell = data.cell(cells, i);
                    st.put(c.storeAbs(), 0x0400 + cell, code, false); // STX screen
                    st.put(c.storeAbs(), 0xD800 + cell, INK, true); // STY colour
                }
                c.rd(3); // JMP next ring
            } else {
                c.rd(5); // BNE not taken, JMP restore
                for (0..cells.len / 2) |i| {
                    const cell = data.cell(cells, i);
                    c.rd(4); // LDA $7400+cell
                    st.put(c.storeAbs(), 0x0400 + cell, d.screen()[cell], false);
                    c.rd(4); // LDA $7800+cell
                    st.put(c.storeAbs(), 0xD800 + cell, d.colour()[cell], true);
                }
            }
        }
        c.rd(6); // RTS
        return c;
    }

    /// $2C00: every third frame the rings move out by one and the centre takes the next code.
    pub fn step(self: *Part1, d: data.Part1) void {
        if (self.done) return;
        self.wait -= 1;
        if (self.wait != 0) return;
        self.wait = 3;
        var k: usize = RINGS - 1;
        while (k > 0) : (k -= 1) self.ring[k] = self.ring[k - 1];
        self.ring[0] = d.feed()[self.fed];
        self.fed += 1;
        if (self.fed == FEED) self.done = true;
    }
};
