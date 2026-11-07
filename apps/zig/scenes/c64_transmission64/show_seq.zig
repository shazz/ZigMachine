// --------------------------------------------------------------------------
// What each frame of the main sequence emits (show.zig runs it): the IRQ chains of the parts
// and the wipes, and the main loop's few visible steps between them.
// --------------------------------------------------------------------------
const vic = @import("vic.zig");
const Clock = @import("clock.zig").Clock;
const Show = @import("show.zig").Show;

pub const State = enum { part1, off, wipe, part2_init, part2, part3 };

// From part 1's $2C80 returning to the IRQ's $D012 write ($2C00 and the tail): VICE frame 726.
const P1_TAIL = 37;
// From that write to the main loop's $D011 = $0B (the RTI and the wait loop's exit).
const P1_MAIN = 55;
// Part 2's first frame (the wipe's $09CE IRQ, then $4000's register set-up) and the frame its
// init turns the bitmap on ($D011 = $3B on line 45; the logo is all purple until coloured).
const P2_INIT = 866;
const P2_ON = 870;

pub fn emit(s: *Show) void {
    switch (s.state) {
        .part1 => part1(s),
        .off => off(s),
        .wipe => wipe(s),
        .part2_init => part2Init(s),
        .part2 => part2(s),
        .part3 => s.p3.pre(s.frames, &s.q),
    }
}

// $2B7B on line 248: the music, the rings ($2C80, timed), the step ($2C00).
fn part1(s: *Show) void {
    const start = @as(u32, 248) * vic.CYCLES + s.d.part1.start(s.frames);
    var c = Clock.atTime(start, true);
    c = s.p1.draw(c, &s.st, s.d.part1);
    s.p1.step(s.d.part1);
    const t = c.time() + P1_TAIL;
    s.q.at(0, t, 0x12, 0xF8);
    if (!s.p1.done) return;
    s.q.at(0, t + P1_MAIN, 0x11, 0x0B);
    s.state = .off;
}

// $0986: ten frames of music with the screen off, then the bars from line 0.
fn off(s: *Show) void {
    s.q.w(260, 33, 0x11, 0x0B);
    s.q.w(260, 39, 0x15, 0x00);
    s.off_left -= 1;
    if (s.off_left != 0) return;
    s.off_left = 10;
    s.wipe.bars_line = 0;
    s.state = .wipe;
}

fn wipe(s: *Show) void {
    if (s.wipe_skip) {
        s.wipe_skip = false;
        return;
    }
    s.wipe.bars(&s.q);
    const r = s.wipe.irq2(&s.q, s.d.wipe);
    s.wipe_skip = r.skip;
    if (!r.done) return;
    s.wipes += 1;
    s.state = if (s.wipes == 1) .part2_init else .part3;
}

// $09CE (line 251) releases the main loop: part 2's init sets the registers, fills the screen
// and draws the logo (screen off, then all purple: when its bytes land does not show).
fn part2Init(s: *Show) void {
    const d = s.d.part2;
    if (s.frames == P2_INIT) {
        for ([_][3]u8{ .{ 37, 0x11, 0x0B }, .{ 43, 0x15, 0x00 } }) |w| s.q.w(263, w[0], w[1], w[2]);
        const regs = d.vicRegs();
        for ([_][2]u8{ .{ 25, 0x16 }, .{ 31, 0x18 }, .{ 49, 0x20 }, .{ 53, 0x21 } }) |w| s.q.w(265, w[0], w[1], regs[w[1]]);
        s.q.w(265, 43, vic.BANK, 0xC7);
        return;
    }
    if (s.frames == P2_INIT + 1) {
        @memcpy(s.ram[0x2000..0x3F40], d.bitmap());
        @memcpy(s.ram[0x0400..0x07E8], d.screen());
        @memcpy(s.col[0..1000], d.colour());
        s.vic.dirty.touch();
    }
    if (s.frames == P2_ON) {
        s.q.w(45, 10, 0x11, 0x3B);
        s.state = .part2;
        part2(s);
    }
}

fn part2(s: *Show) void {
    const d = s.d.part2;
    const n = s.frames;
    const ev0 = d.event(0); // the logo's overlay done: the antenna sprite set up
    if (n == ev0[0]) {
        const t: u32 = ev0[1];
        for ([_][2]u8{ .{ 0x25, 4 }, .{ 0x26, 4 }, .{ 0x00, 0xB8 }, .{ 0x01, 0x89 }, .{ 0x1C, 1 }, .{ 0x15, 1 } }, 0..) |w, k|
            s.q.at(0, t + 6 * @as(u32, @intCast(k)) + 6, w[0], w[1]);
        s.ram[0x07F8] = 0x80;
        s.vic.dirty.touch();
    }
    s.p2.mainLoop(n, &s.q, &s.st, d);
    s.p2.irq(n, &s.q, &s.st, d);
    const ev1 = d.event(1); // the return to the main loop: screen off, the second wipe
    if (n == ev1[0]) {
        s.q.at(0, @as(u32, ev1[1]) + 9, 0x11, 0x0B);
        s.off_left = 10; // the wipe's code patched itself for the second run (wipe.zig)
        s.state = .off;
        off(s); // $0986 already runs on this frame's line 251

    }
}
