// --------------------------------------------------------------------------
// The transitions ($0986, $0861, $08CB, $09CE): border bars wipe the screen while the main
// loop decrunches the next part. Screen off throughout: every visible line is border colour.
//
// $0986 (line 248, ten frames): the music, screen off. Then two IRQs a frame:
//   $0861 at line L: seven border colours, one per bar, each a delay routine apart: the
//         delay routines at $0A9D.. take 1..8 whole lines (63n cycles), so the bars are 1..8
//         lines thick; the colour above them is the last one $08CB set, below them the last bar's.
//   $08CB at line 292 (or 308 when L >= 256, 300 the first time): two colours (off screen),
//         the music, then the next frame's L from $0B00/$0B80 (128 frames of an easing curve)
//         and the bars' delay from $0A0D. Its D012 write lands ~12 lines in; the first time
//         (line 300 + 12 = next frame's line 0) it misses L = 0 and that frame has no bars.
// After 128 steps $09CE (line 251) releases the main loop. The code then patches its own
// colours, so the second wipe (after part 2) runs from purple to black, not light blue to purple.
// All the timings are VICE's (prototypes/transmission64_re/vice/w1 traces).
// --------------------------------------------------------------------------
const vic = @import("vic.zig");
const data = @import("data.zig");

pub const STEPS = 128;
const IRQ2_LEN = 12; // lines from $08CB's start to its D012 write (the music between)

pub const Colours = struct {
    bars: [7]u8, // $0877, $087F, $0887, $088F, $0897, $089F, $08A7
    low: [2]u8, // $08CB's two colours when L < 256: $0912, $0917
    high: u8, // ...when L >= 256: $0902 (both)
};

pub const FIRST = Colours{ .bars = .{ 0x0B, 0x06, 0x00, 0x06, 0x0B, 0x04, 0x0E }, .low = .{ 0x0E, 0x04 }, .high = 0x04 };
// what $08CB patches in when the first wipe ends
pub const SECOND = Colours{ .bars = .{ 0x00, 0x00, 0x00, 0x06, 0x0B, 0x04, 0x04 }, .low = .{ 0x04, 0x00 }, .high = 0x00 };

pub const Wipe = struct {
    col: Colours = FIRST,
    x: u8 = 0, // $08EB: the step
    gap: u16 = 1, // lines between bars (delay routine $0A9D.. patched in)
    bars_line: u16 = 0, // $D012 for $0861 (0 the first time: $0986 sets it)
    irq2_line: u16 = 300, // $08B1: $2C, then $24 / $34
    irq2_cols: [2]u8 = .{ 0x0E, 0x0E }, // $08DE, $08E6 (what the first run writes)

    /// Lines a delay routine takes: $9D 1, $A5 2, $AD 3, $B8 4, $C3 5, $CE 6, $D9 7, $E6 8.
    pub fn delayLines(lo: u8) u16 {
        return switch (lo) {
            0x9D => 1,
            0xA5 => 2,
            0xAD => 3,
            0xB8 => 4,
            0xC3 => 5,
            0xCE => 6,
            0xD9 => 7,
            0xE6 => 8,
            else => @panic("wipe: not a delay routine"), // $0A0D holds only these
        };
    }

    /// $0861 at `bars_line`: the seven colours, then $08CB set for `irq2_line` (line + 256).
    pub fn bars(self: *const Wipe, q: *vic.Queue) void {
        var line = self.bars_line + 1;
        for (self.col.bars, 0..) |c, k| {
            if (k > 0) line += self.gap;
            q.w(line, 7, 0x20, c);
        }
        q.w(line, 13, 0x11, 0x8B);
        q.w(line, 19, 0x12, @truncate(self.irq2_line));
    }

    /// $08CB: its colours, then the next step. Returns true when the wipe is over (the IRQ
    /// goes to $09CE at line 251) and whether the next frame misses its bars.
    pub fn irq2(self: *Wipe, q: *vic.Queue, d: data.Wipe) struct { done: bool, skip: bool } {
        const l = self.irq2_line;
        q.w(l, 41, 0x20, self.irq2_cols[0]);
        q.w(l + IRQ2_LEN, 29, 0x20, self.irq2_cols[1]);
        const next = d.line(self.x);
        q.w(l + IRQ2_LEN, 39, 0x12, @truncate(next));
        q.w(l + IRQ2_LEN, 49, 0x11, if (next >= 256) 0x8B else 0x0B);
        if (next >= 256) {
            self.irq2_line = 308;
            self.irq2_cols = .{ self.col.high, self.col.high };
        } else {
            self.irq2_line = 292;
            self.irq2_cols = self.col.low;
        }
        // the D012 write is at line l + 12: past the frame, a line 0..that misses this frame
        const skip = l + IRQ2_LEN >= vic.LINES and next <= l + IRQ2_LEN - vic.LINES;
        self.bars_line = next;
        self.gap = delayLines(d.delay(self.x));
        self.x = (self.x + 1) & 0x7F;
        if (self.x != 0) return .{ .done = false, .skip = skip };
        self.col = SECOND;
        self.irq2_line = 300; // $08B1 = $2C again
        self.gap = 1;
        return .{ .done = true, .skip = false };
    }
};
