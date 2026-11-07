// --------------------------------------------------------------------------
// The invitation's main sequence ($080E): part 1, a wipe while part 2 decrunches, part 2, a
// wipe while part 3 decrunches, part 3. One step() is one PAL frame (raster lines 0..311): the
// IRQ chains emit their register writes and their timed stores, the VIC model runs them.
//
// Frame numbers are VICE's from part 1's first IRQ ($2B7B, line 248): frame 1 holds it (what
// came before is the drive upload, 33 or 34 frames depending on the drive). Part 1 runs
// frames 1..726; its last IRQ ends on frame 727's line 85 and the main loop turns the screen
// off; $0986 plays the tune for frames 727..736; the bars wipe frames 737..865 (none on 738);
// part 2 starts on frame 866 (its init: screen off until 870, the logo all purple until the
// colours come), returns to the main loop on frame 3012; the second wipe follows the same way.
// --------------------------------------------------------------------------
pub const vic = @import("vic.zig");
pub const data = @import("data.zig");
const Clock = @import("clock.zig").Clock;
const Part1 = @import("part1.zig").Part1;
const Part2 = @import("part2.zig").Part2;
const Part3 = @import("part3.zig").Part3;
const wipe_mod = @import("wipe.zig");
const seq = @import("show_seq.zig");

pub const State = seq.State;

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
    p2: Part2 = .{},
    p3: Part3 = undefined,
    off_left: u8 = 10, // $09A9
    wipe: wipe_mod.Wipe = .{},
    wipe_skip: bool = false,
    wipes: u8 = 0, // wipes finished

    /// The machine as it is at frame 1 (part 1's init has run). `self` must not move after.
    pub fn init(self: *Show, d: data.Data) void {
        // field by field: a whole-struct assignment would build the 128 KB of buffers twice
        self.d = d;
        self.vic = vic.Vic.init(d.part1.vicRegs(), d.part1.dd00());
        self.q.n = 0;
        self.st.reset();
        self.state = .part1;
        self.frames = 0;
        self.p1 = .{};
        self.p2 = Part2.init(d.part2);
        self.p3 = Part3.init(d.part3);
        self.off_left = 10;
        self.wipe = .{};
        self.wipe_skip = false;
        self.wipes = 0;
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
        self.emit();
        self.run(out);
    }

    /// The frame's writes and stores (the tools look at them before they run).
    pub fn emit(self: *Show) void {
        self.frames += 1;
        seq.emit(self);
    }

    pub fn run(self: *Show, out: *vic.Out) void {
        const done = self.vic.frame(&self.q, self.st.items(), self.mem(), out);
        self.st.carry(done, vic.FRAME);
        self.q.carry();
        if (self.state == .part3) {
            self.p3.post(self.frames, &self.ram, &self.col, self.d.part3);
            self.vic.dirty.touch(); // part 3 draws straight into the RAM copy
        }
    }
};

// The character ROM is never what the VIC reads in this invitation (no part shows bank 0's
// $1000-$1FFF): part 1 copies its upper case set to $2000 (ripped from there).
const NO_ROM = [_]u8{0} ** 4096;
