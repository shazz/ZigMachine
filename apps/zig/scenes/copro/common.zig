// --------------------------------------------------------------------------
// COPRO: what every page shares. One plane, 320x200: the effect in rows
// 0..ROWS-1, the HUD under it. Palette: 0..15 the picture's (or the page's
// own), 16..31 the effect's shades, 32..35 the HUD's.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const job = zg.bard.job;

pub const W: u32 = 320;
pub const ROWS: u32 = 176; // the effect's rows; the HUD's are 176..199
pub const SHADE: u8 = 16;
pub const HUD_BG: u8 = 32;
pub const HUD_INK: u8 = 33;
pub const HUD_HI: u8 = 34;
pub const HUD_DIM: u8 = 35;

extern fn hostMicros() u32;

/// The board's clock in microseconds (decisions.md 2026-10-10); 0 in the harnesses: nothing timed.
pub fn micros() u32 {
    return hostMicros();
}

/// A page's view of the cart: its plane, the frame, where jobs run, and what the frame's job cost.
pub const Ctx = struct {
    os: *zg.ZigOS,
    fb: *zg.LogicalFB,
    frame: u32 = 0,
    where: job.Where = .coprocessor,
    /// Microseconds ZIGGY spent this frame posting (on .ziggy: serving) jobs, and waiting for them.
    post_us: u32 = 0,
    wait_us: u32 = 0,
    /// The server's cycles on the last job answered (BARD's counter; 0 where none is counted).
    job_cycles: u32 = 0,

    pub fn pixels(self: *Ctx) [*]u8 {
        return self.fb.fb;
    }

    /// Post a job and count what it cost ZIGGY (all of it on .ziggy: the cart serves it there).
    pub fn post(self: *Ctx, op: job.Op, args: []const u32) u32 {
        const t0 = micros();
        const t = job.post(op, args);
        self.post_us +%= micros() -% t0;
        return t;
    }

    /// Wait for job `t` (none: no-op) and take its answer.
    pub fn wait(self: *Ctx, t: ?u32) ?*volatile job.Job {
        const n = t orelse return null;
        const t0 = micros();
        job.wait(n);
        self.wait_us +%= micros() -% t0;
        const j = job.result(n);
        self.job_cycles = j.cycles;
        return j;
    }
};

/// The effect's shades (16..31): `from` to `to`, linear.
pub fn shades(fb: *zg.LogicalFB, from: [3]u8, to: [3]u8) void {
    for (0..16) |i| {
        var c: [3]u8 = undefined;
        for (0..3) |k| {
            const a: i32 = from[k];
            const b: i32 = to[k];
            c[k] = @intCast(a + @divTrunc((b - a) * @as(i32, @intCast(i)), 15)); // init only: 16 entries
        }
        fb.setPaletteEntry(SHADE + @as(u8, @intCast(i)), .{ .r = c[0], .g = c[1], .b = c[2], .a = 255 });
    }
}

/// The effect's rows to colour `v` (a page's entry).
pub fn clearRows(fb: *zg.LogicalFB, v: u8) void {
    @memset(fb.fb[0 .. ROWS * W], v);
}

/// A u32 array in the cart's RAM arena: word-aligned, as every job array must be (BARD traps a misaligned word).
pub fn words(n: usize) []u32 {
    return zg.mem.mustAlloc(u32, n);
}
