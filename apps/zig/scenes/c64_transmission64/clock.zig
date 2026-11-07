// --------------------------------------------------------------------------
// The 6510's clock against the beam: where each store of a routine lands.
//
// A routine's stores race the VIC (vic.zig applies each at its time), so the port times them
// the way the C64 does: one cycle per bus access, and on a bad line (screen on, lines 51..250
// at (line & 7) == 3) the VIC takes the bus from cycle 12 to 54: a READ cycle there waits for
// cycle 55, a write goes through (the 6510 only stops on reads). Checked against VICE's store
// trace of part 1's ring routine: every one of ~1700 stores a frame at its traced cycle
// (prototypes/transmission64_re/ANALYSIS.md). Sprite DMA is not counted: no routine that
// races the beam here runs with a sprite on screen.
// --------------------------------------------------------------------------
const vic = @import("vic.zig");

pub const Clock = struct {
    line: u16, // may run past 311: the routine goes on into the next frame
    cyc: u8,
    screen_on: bool, // DEN: bad lines happen

    pub fn at(line: u16, cyc: u8, screen_on: bool) Clock {
        return .{ .line = line, .cyc = cyc, .screen_on = screen_on };
    }

    /// Beam time in cycles from line 0 of the frame the clock started in.
    pub fn time(self: Clock) u32 {
        return @as(u32, self.line) * vic.CYCLES + self.cyc;
    }

    fn bad(self: Clock) bool {
        const l = self.line % vic.LINES;
        return self.screen_on and l >= vic.WIN_TOP and l < vic.WIN_TOP + vic.WIN_LINES and (l - vic.WIN_TOP) % 8 == 0;
    }

    fn tick(self: *Clock) void {
        self.cyc += 1;
        if (self.cyc == vic.CYCLES) {
            self.cyc = 0;
            self.line += 1;
        }
    }

    /// `n` read cycles.
    pub fn rd(self: *Clock, n: u8) void {
        for (0..n) |_| {
            if (self.cyc >= 12 and self.cyc < 55 and self.bad()) self.cyc = 55;
            self.tick();
        }
    }

    /// One write cycle; returns its beam time.
    pub fn wr(self: *Clock) u32 {
        const t = self.time();
        self.tick();
        return t;
    }

    /// `STA/STX/STY abs`: three reads, the write. Returns the store's time.
    pub fn storeAbs(self: *Clock) u32 {
        self.rd(3);
        return self.wr();
    }
};
