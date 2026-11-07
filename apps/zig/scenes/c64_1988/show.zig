// --------------------------------------------------------------------------
// The intro's main loop ($1E00): part 1 (logo, $5300), part 2 (wipe, $E200), part 3 (grid,
// $4000), forever; each part's IRQ chain raises $1FFE when it is done, the main loop zeroes
// the frame counter ($1FFC/$1FFD) and starts the next part. One step() is one PAL frame
// (raster lines 0..311): the parts emit their writes, the sprite unit runs them.
//
// Frame numbers are VICE's (frame 1 holds the $1E00 entry): the loop is 2183 frames, part 1
// 1643 (text 1, 2, 3 in turn), part 2 70, part 3 468 (cubes, then balls next time), and the
// init frames between: each part's init waits for line 256 and then line 0, so a part
// starts one or two frames after the last one ended, as the trace shows.
// --------------------------------------------------------------------------
pub const vic = @import("vic.zig");
const data = @import("data.zig");
pub const Data = data.Data;
pub const RIPPED_LEN = data.RIPPED_LEN;
const Logo = @import("logo.zig").Logo;
const Wipe = @import("wipe.zig").Wipe;
const Grid = @import("grid.zig").Grid;

pub const State = enum { logo_a, logo_b, logo, wipe, grid_b, grid, grid_over, idle };

pub const Show = struct {
    data: Data,
    vic: vic.Vic,
    q: vic.Queue = .{},
    state: State = .logo_a,
    counter: u16 = 0, // $1FFC/$1FFD
    frames: u32 = 0, // frames run (VICE's frame number of the last one)
    logo: Logo = .{},
    wipe: Wipe = .{},
    grid: Grid = .{},
    foreign: u32 = 0,

    pub fn init(d: Data) Show {
        return .{ .data = d, .vic = vic.Vic.init(d.vicInit()) };
    }

    pub fn mem(self: *Show) vic.Mem {
        return .{ .bank3 = self.data.bank3, .bank0_2000 = self.data.bank0, .foreign = &self.foreign };
    }

    /// Emit and run one frame into `out`.
    pub fn step(self: *Show, out: *vic.Out) void {
        self.q.n = 0;
        self.emit();
        self.frames += 1;
        self.vic.frame(&self.q, self.mem(), out);
    }

    fn emit(self: *Show) void {
        const q = &self.q;
        const d = self.data;
        switch (self.state) {
            .logo_a => {
                self.logo.initA(q, if (self.frames == 0) 16 else 0);
                self.state = .logo_b;
            },
            .logo_b => {
                self.counter = 0;
                self.logo.initB(q, d);
                self.state = .logo;
            },
            .logo => if (self.logo.frame(q, &self.counter, d)) {
                self.counter = 0;
                self.wipe.init(q);
                self.state = .wipe;
            },
            .wipe => if (self.wipe.frame(q)) {
                self.counter = 0;
                self.grid.initA(q);
                self.state = .grid_b;
            },
            .grid_b => self.gridDone(self.grid.initB(q, &self.counter, d)),
            .grid => self.gridDone(self.grid.frame(q, &self.counter, d)),
            .grid_over => self.state = .logo_a,
            .idle => {},
        }
    }

    // The grid's end handler raises the flag on the next frame's line 12; the main loop then
    // sets $D011 to $1B (screen on, 25 rows) and waits two frame tops for part 1's init.
    fn gridDone(self: *Show, done: bool) void {
        if (!done) {
            self.state = .grid;
            return;
        }
        self.q.w(312 + 21, 28, 0x11, 0x1B);
        self.state = .grid_over;
    }
};
