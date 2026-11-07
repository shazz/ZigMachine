// --------------------------------------------------------------------------
// Part 3 ($4000): 8 columns of bouncing cubes (variant A, the first time) or balls (B, the
// next), 7 bands down the whole open screen: 56 sprites from 8, two shapes a sprite (each
// block holds two objects, X-expanded). Columns join from the right one every 18 frames;
// the grid scrolls 3 pixels a frame (18-step tables) and animates every 2nd frame.
// After 300 frames the colours fade out in 9 steps of 10 frames, then the part ends.
//
// The end-of-frame handler (line 284 on) sets the next frame up: sprites off, X and MSB,
// pointers, the 35 masks (each column clears its bit in the 20 lines its bounce table puts
// it at), the music, the join and fade counters. It runs past line 311: its last writes
// (the fade's colours, $D011) land on the next frame's top lines, as on the C64.
// --------------------------------------------------------------------------
const vic = @import("vic.zig");
const T = @import("tables.zig");
const Data = @import("data.zig").Data;
const bands = @import("grid_bands.zig");

const NEXT = 312; // lines past the frame's end belong to the next frame
pub const FADE_AT: u16 = 300;

pub const Grid = struct {
    balls: bool = false, // $4C7C: the variant the NEXT run uses (A cubes first)
    anim_len: u8 = 10, // $4C7D
    ptrtab: [27]u8 = .{0} ** 27, // $4C7E: animation frames (sprite blocks)
    bounce: [216]u8 = .{0} ** 216, // $4CBF: this variant's bounce table
    step: u8 = 0, // $60: the grid's scroll step (17..0)
    frame_no: u8 = 0, // $61
    col: [8]u8 = .{0} ** 8, // $62..$69: each column's animation frame
    joined: u8 = 7, // $6B: columns below this one are still blank
    half: u8 = 0, // $4C99
    tick: u8 = 0, // $4C9A (shared by the join and fade counters, as in the original)
    faded: bool = false, // $4C9C
    fade_step: u8 = 0, // $4CBD
    masks: [bands.ROWS]u8 = .{0xFF} ** bands.ROWS, // $6C..

    /// The main loop's frame after part 2 (lines 10-119): blue, bank 0, screen $0400
    /// cleared to $20 (so the pointers too), screen on until the init's second frame.
    pub fn initA(_: *Grid, q: *vic.Queue) void {
        q.at(11, 16, 0x20, 6);
        q.at(11, 22, 0x21, 6);
        q.at(11, 28, vic.BANK, 3);
        q.at(11, 34, 0x18, 0x18);
        const clear = [8]u16{ 116 * 63 + 33, 116 * 63 + 58, 117 * 63 + 20, 117 * 63 + 45, 118 * 63 + 7, 118 * 63 + 32, 118 * 63 + 57, 119 * 63 + 19 };
        for (clear, 0..) |t, s| q.at(0, t, vic.PTR0 + @as(u8, @intCast(s)), 0x20);
        q.at(119, 29, 0x11, 0x18);
    }

    /// The init's second frame ($4031 on): sprite registers, this run's variant, the
    /// tables; IRQ at line 247, so the bottom band and the end handler run this frame.
    pub fn initB(self: *Grid, q: *vic.Queue, counter: *u16, d: Data) bool {
        for ([_]u8{ 0x1D, 0x17, 0x1B }, 0..) |r, i| q.at(0, 16 + 4 * @as(u16, @intCast(i)), r, 0);
        for (0..8) |s| q.at(0, 31 + 7 * @as(u16, @intCast(s)), 1 + 2 * @as(u8, @intCast(s)), 0);
        for (0..8) |s| q.at(2, 4 + 4 * @as(u16, @intCast(s)), 2 * @as(u8, @intCast(s)), 0xFF);
        q.at(2, 36, 0x10, 0xFF);
        q.at(2, 47, 0x1C, 0xFF);
        for (0..8) |s| q.at(2, 53 + 6 * @as(u16, @intCast(s)), vic.PTR0 + @as(u8, @intCast(s)), 0x94);
        self.variant(q, d);
        q.at(if (self.balls) 95 else 98, 45, 0x15, 0); // B's copy loop just ran: `balls` is the next run's
        self.step = 0x13;
        self.frame_no = 0;
        self.joined = 7;
        self.half = 0;
        self.tick = 0;
        self.faded = false;
        self.fade_step = 0;
        self.masks = .{0xFF} ** bands.ROWS;
        bands.bottom(q, &self.masks);
        return self.end(q, counter, d);
    }

    // L4216 (A: cubes, yellow) or L4109 (B: balls, light blue), alternating run to run.
    fn variant(self: *Grid, q: *vic.Queue, d: Data) void {
        const b = self.balls;
        for (0..8) |s| q.at(4, 9 + 6 * @as(u16, @intCast(s)), 0x27 + @as(u8, @intCast(s)), if (b) 0x0E else 0x07);
        q.at(5, 5, 0x25, 0x0E);
        q.at(5, 11, 0x26, if (b) 0x01 else 0x03);
        const first: u8 = if (b) 0x8B else 0x80;
        for (0..8) |s| q.at(5, 17 + 4 * @as(u16, @intCast(s)), vic.PTR0 + @as(u8, @intCast(s)), first);
        const n: u8 = if (b) 13 else 10;
        for (0..n) |i| {
            self.ptrtab[i] = first + @as(u8, @intCast(i));
            self.ptrtab[n + i] = first + @as(u8, @intCast(i));
        }
        self.ptrtab[2 * n] = first + n;
        self.col = .{2 * n} ** 8; // the blank frame after the loop's two copies
        self.anim_len = n;
        self.bounce = if (b) T.bounce_b else d.bounceA().*;
        self.balls = !b;
    }

    /// One frame: the top bands (masks from the last end handler), the bottom band, the
    /// end handler. True when the part has ended (on the next frame's line 12).
    pub fn frame(self: *Grid, q: *vic.Queue, counter: *u16, d: Data) bool {
        bands.top(q, &self.masks);
        bands.bottom(q, &self.masks);
        return self.end(q, counter, d);
    }

    fn end(self: *Grid, q: *vic.Queue, counter: *u16, d: Data) bool {
        q.w(284, 32, 0x15, 0);
        self.step = if (self.step == 0) 0x11 else self.step - 1;
        self.position(q);
        for (0..8) |c| q.at(287, 7 + 11 * @as(u16, @intCast(c)), vic.PTR0 + @as(u8, @intCast(c)), self.ptrtab[self.col[c]]);
        self.animate();
        for (0..8) |s| q.at(289, 11 + 4 * @as(u16, @intCast(s)), 1 + 2 * @as(u8, @intCast(s)), bands.Y_TOP[0]);
        self.newMasks();
        self.join();
        return self.counters(q, counter, d);
    }

    // X and MSB of the 8 columns from the 18-step tables. The first frame reads index 18:
    // one past each column's 18, i.e. the next column's first (and past the last, the MSB
    // table's first byte, 1, then $52EF, 0), as the 6510 did.
    fn position(self: *Grid, q: *vic.Queue) void {
        var msb: u8 = 0;
        for (0..8) |c| {
            const i = 18 * c + self.step;
            const lo: u8 = if (i < 144) @truncate(T.grid_x[i / 18][i % 18]) else 1;
            const hi: u8 = if (i < 144) @intCast(T.grid_x[i / 18][i % 18] >> 8) else 0;
            const cy: u16 = 15 + 8 * @as(u16, @intCast(c)) + @intFromBool(c >= 2);
            q.at(285, cy, 2 * @as(u8, @intCast(c)), lo);
            msb |= hi << @intCast(c);
        }
        q.at(286, 59, 0x10, msb);
    }

    fn animate(self: *Grid) void {
        self.half += 1;
        if (self.half == 2) {
            self.half = 0;
            self.frame_no += 1;
            if (self.frame_no == self.anim_len) self.frame_no = 0;
        }
        for (self.joined..8) |c| self.col[c] = self.frame_no;
    }

    // L4B6F + L480E: all held, then each column runs its 20 rows from its bounce offset.
    fn newMasks(self: *Grid) void {
        var m: [70]u8 = .{0xFF} ** 70;
        for (0..8) |c| {
            const y = self.bounce[self.step + 18 * c];
            for (0..20) |j| m[y + j] &= ~(@as(u8, 1) << @intCast(c));
        }
        self.masks = m[0..bands.ROWS].*;
    }

    // L4BFE: every 18 frames one more column (from the right) starts animating.
    fn join(self: *Grid) void {
        self.tick +%= 1;
        if (self.tick != 18) return;
        self.tick = 0;
        if (self.joined != 0) self.joined -= 1;
    }

    fn counters(self: *Grid, q: *vic.Queue, counter: *u16, d: Data) bool {
        if (counter.* != FADE_AT) {
            counter.* += 1;
            return self.rearm(q);
        }
        self.tick +%= 1; // L4C19, on the same counter the join uses (8 bits: it can run round)
        if (self.tick == 10) {
            self.tick = 0;
            self.fadeColours(q, d.gridFade());
            if (self.fade_step == 8) self.faded = true else self.fade_step += 1;
        }
        return if (self.faded) true else self.rearm(q);
    }

    // L4C3E: step y of the fade. The border reads one past its 8 steps at y = 8: $4CBD itself.
    fn fadeColours(self: *Grid, q: *vic.Queue, f: *const [32]u8) void {
        const y = self.fade_step;
        q.w(NEXT + 10, 49, 0x25, f[y]);
        q.w(NEXT + 10, 57, 0x26, f[8 + y]);
        for (0..8) |s| q.w(NEXT + 11, 2 + 4 * @as(u8, @intCast(s)), 0x27 + @as(u8, @intCast(s)), f[16 + y]);
        const border = if (y < 8) f[24 + y] else y;
        q.w(NEXT + 11, 38, 0x20, border);
        q.w(NEXT + 11, 42, 0x21, border);
    }

    fn rearm(_: *Grid, q: *vic.Queue) bool {
        q.w(NEXT + 11, 17, 0x11, 0x0B);
        q.w(NEXT + 11, 51, 0x11, 0x0B);
        return false;
    }
};
