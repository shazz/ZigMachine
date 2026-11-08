// --------------------------------------------------------------------------
// Which window lines must be drawn again: Matt's rule, "only modify what needs to be modified".
//
// A line's pixels are a function of the registers it is drawn with, its row's latched screen
// bytes and colours, the rest of the VIC's memory (charsets, bitmap, sprite data) and the
// sprites over it. So a line is skipped when all of these are as they were when it was last
// drawn: the registers (two keys), the latched row (compared byte for byte), a memory epoch
// (bumped by any store that changes VIC memory outside the screen rows, and by `touch` after a
// part writes RAM directly), and no sprite over it this frame or the last.
// --------------------------------------------------------------------------
pub const LINES = 200;
pub const ROWS = 25;

pub const Dirty = struct {
    key_a: [LINES]u32 = .{0xFFFF_FFFF} ** LINES, // $D011 $D016 $D018 bank, at the line's draw
    key_b: [LINES]u32 = .{0xFFFF_FFFF} ** LINES, // $D021-$D024
    epoch_at: [LINES]u32 = .{0} ** LINES,
    sprite_at: [LINES]bool = .{false} ** LINES, // a sprite covered the line last frame
    latched: [ROWS][80]u8 = .{.{0} ** 80} ** ROWS, // each row's screen bytes and colours, last latch
    row_new: [ROWS]bool = .{true} ** ROWS, // the row latched different bytes this frame
    epoch: u32 = 1,

    /// A part wrote the C64's memory directly: everything may have changed.
    pub fn touch(self: *Dirty) void {
        self.epoch +%= 1;
    }

    /// The row's latch, compared with the last one.
    pub fn latch(self: *Dirty, row: usize, vm: *const [40]u8, cm: *const [40]u8) void {
        const old = &self.latched[row];
        var same = true; // byte by byte: std.mem.eql's wide loads would be misaligned here
        for (0..40) |c| {
            if (old[c] != vm[c] or old[40 + c] != cm[c]) {
                same = false;
                break;
            }
        }
        self.row_new[row] = !same;
        if (same) return;
        @memcpy(old[0..40], vm);
        @memcpy(old[40..80], cm);
    }

    /// Whether window line `wl` must be drawn (and if so, remember what it is drawn with).
    pub fn need(self: *Dirty, wl: usize, reg: *const [0x2F]u8, bank: u8, sprite: bool, was_window: bool) bool {
        const a = @as(u32, reg[0x11] & 0x7F) | @as(u32, reg[0x16]) << 8 | @as(u32, reg[0x18]) << 16 | @as(u32, bank) << 24;
        const b = @as(u32, reg[0x21] & 15) | @as(u32, reg[0x22] & 15) << 4 | @as(u32, reg[0x23] & 15) << 8 | @as(u32, reg[0x24] & 15) << 12;
        const had_sprite = self.sprite_at[wl];
        self.sprite_at[wl] = sprite;
        const same = was_window and !sprite and !had_sprite and !self.row_new[wl / 8] and
            self.key_a[wl] == a and self.key_b[wl] == b and self.epoch_at[wl] == self.epoch;
        if (same) return false;
        self.key_a[wl] = a;
        self.key_b[wl] = b;
        self.epoch_at[wl] = self.epoch;
        return true;
    }
};
