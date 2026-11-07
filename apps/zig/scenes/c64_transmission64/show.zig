// --------------------------------------------------------------------------
// The invitation's main sequence ($080E): part 1, a wipe while part 2 decrunches, part 2, a
// wipe while part 3 decrunches, part 3. One step() is one PAL frame (raster lines 0..311): the
// IRQ chains emit their register writes and their timed stores, the VIC model runs them.
//
// Frame numbers are VICE's from part 1's first IRQ ($2B7B, line 248): frame 1 holds it (what
// came before is the drive upload, 33 or 34 frames depending on the drive). Part 1 runs
// frames 1..726; its last IRQ ends on frame 727's line 85 and the main loop turns the screen
// off; $0986 plays the tune for frames 727..736; the bars wipe frames 737..865 (none on 738);
// part 2 starts on frame 866.
// --------------------------------------------------------------------------
pub const vic = @import("vic.zig");
pub const data = @import("data.zig");
const Clock = @import("clock.zig").Clock;
const Part1 = @import("part1.zig").Part1;
const wipe_mod = @import("wipe.zig");

pub const State = enum { part1, off, wipe, part2 };

// From part 1's $2C80 returning to the IRQ's $D012 write ($2C00 and the tail): VICE frame 726.
const P1_TAIL = 37;
// From that write to the main loop's $D011 = $0B (the RTI and the wait loop's exit).
const P1_MAIN = 55;

pub const Show = struct {
    d: data.Data,
    vic: vic.Vic,
    ram: [65536]u8 = undefined,
    col: [1024]u8 = undefined,
    q: vic.Queue = .{},
    st: vic.Stores = .{},
    state: State = .part1,
    frames: u32 = 0, // frames run (VICE's number of the last one)
    p1: Part1 = .{},
    off_left: u8 = 10, // $09A9
    wipe: wipe_mod.Wipe = .{},
    wipe_skip: bool = false,

    /// The machine as it is at frame 1 (part 1's init has run). `self` must not move after.
    pub fn init(self: *Show, d: data.Data) void {
        self.* = .{ .d = d, .vic = vic.Vic.init(d.part1.vicRegs(), d.part1.dd00()) };
        @memset(&self.ram, 0);
        @memset(&self.col, 0);
        @memcpy(self.ram[0x0400..0x07E8], d.part1.screen());
        @memcpy(self.col[0..1000], d.part1.colour());
        @memcpy(self.ram[0x2000..0x2800], d.part1.charset());
    }

    pub fn mem(self: *Show) vic.Mem {
        return .{ .ram = &self.ram, .col = &self.col, .chargen = &NO_ROM };
    }

    /// Emit and run one frame into `out`.
    pub fn step(self: *Show, out: *vic.Out) void {
        self.frames += 1;
        self.emit();
        const done = self.vic.frame(&self.q, self.st.items(), self.mem(), out);
        self.st.carry(done, vic.FRAME);
        self.q.carry();
    }

    fn emit(self: *Show) void {
        switch (self.state) {
            .part1 => self.part1(),
            .off => {
                self.q.w(260, 33, 0x11, 0x0B);
                self.q.w(260, 39, 0x15, 0x00);
                self.off_left -= 1;
                if (self.off_left == 0) {
                    self.off_left = 10;
                    self.wipe.bars_line = 0;
                    self.state = .wipe;
                }
            },
            .wipe => {
                if (self.wipe_skip) {
                    self.wipe_skip = false;
                    return;
                }
                self.wipe.bars(&self.q);
                const r = self.wipe.irq2(&self.q, self.d.wipe);
                self.wipe_skip = r.skip;
                if (r.done) self.state = .part2;
            },
            .part2 => {},
        }
    }

    // $2B7B on line 248: the music, the rings ($2C80, timed), the step ($2C00).
    fn part1(self: *Show) void {
        const start = @as(u32, 248) * vic.CYCLES + self.d.part1.start(self.frames);
        var c = Clock.at(@intCast(start / vic.CYCLES), @intCast(start % vic.CYCLES), true);
        c = self.p1.draw(c, &self.st, self.d.part1);
        self.p1.step(self.d.part1);
        const t = c.time() + P1_TAIL;
        self.q.at(0, t, 0x12, 0xF8);
        if (!self.p1.done) return;
        self.q.at(0, t + P1_MAIN, 0x11, 0x0B);
        self.state = .off;
    }
};

// The character ROM is never what the VIC reads in this invitation (no part shows bank 0's
// $1000-$1FFF): part 1 copies its upper case set to $2000 (ripped from there).
const NO_ROM = [_]u8{0} ** 4096;
