// --------------------------------------------------------------------------
// The blitter's QUEUE (HW 1.8.0, memmap BLIT_CMD_QUEUE): many small ops for
// one hwBlit(). Each op becomes a descriptor in the QUEUE ring (a header and
// the register words it changes); kick() runs the list, flush() runs it and
// waits for it.
//
// Why: on KESTREL a hwBlit() costs ~900 cycles for even an 8x8 fill (the call,
// the wrapper, CHISEL's start and drain). A queued op costs the CPU its few
// ring stores, and CHISEL runs the list back to back while the CPU builds the
// next one (two halves of the ring, like a double buffer).
//
// The contract: a queued op's pixels are only drawn for sure after flush().
// Until then the CPU must not read or write them (nor overwrite a source). In
// the browser the list runs at the kick, on the board CHISEL runs it while the
// cart goes on: a cart that keeps the contract draws the same bytes on both.
//
// Each list starts from the register block as it is at its kick (the machine
// and CHISEL both take a working copy), so the queue keeps `shadow`, that copy
// as its descriptors leave it, read from the block when a list starts: a word
// is stored into the ring only when it changes, and never into the block, so
// the block, and any other code driving the blitter, is left alone.
// --------------------------------------------------------------------------
const hw = @import("hardware");

pub const HALF: usize = hw.BLIT_QUEUE_WORDS / 2; // a list's room: the other half may still be running
pub const Word = struct { k: u5, v: u32 }; // block word k (offset / 4) and its value

// The bits of each word a descriptor sets (memmap BLIT_CMD_QUEUE): word 0's
// MINTERM and CON, the strides' low halves, every other word whole.
fn keep(k: usize) u32 {
    return switch (k) {
        0 => 0x00FF_FF00,
        3, 5, 7, 9 => 0x0000_FFFF,
        else => 0xFFFF_FFFF,
    };
}

pub const Queue = struct {
    base: usize = 0, // the video region (hwVideoBase)
    half: usize = 0, // the ring half the list being built goes into
    n: usize = 0, // its words so far
    pending: bool = false, // a list was kicked and not yet waited for
    shadow: [24]u32 = [_]u32{0} ** 24,

    pub fn init(self: *Queue, base: usize) void {
        self.* = .{ .base = base };
    }

    inline fn reg(self: *const Queue, off: usize) *volatile u32 {
        return @ptrFromInt(self.base + off);
    }

    fn put(self: *Queue, v: u32) void {
        self.reg(hw.OFF_BLIT_QUEUE + 4 * (self.half * HALF + self.n)).* = v;
        self.n += 1;
    }

    // The working copy a new list starts from: the block.
    fn start(self: *Queue) void {
        for (&self.shadow, 0..) |*s, k| s.* = self.reg(hw.OFF_BLIT + 4 * k).* & keep(k);
    }

    /// One op: COMMAND `cmd` (NOP: only set the words) after `words`, which must
    /// come in rising k. Only the words the list does not hold yet go in the ring.
    pub fn op(self: *Queue, cmd: u8, words: []const Word) void {
        if (self.n + 1 + words.len > HALF) self.kick();
        if (self.n == 0) self.start();
        const at = self.n;
        self.put(0); // the header, below
        var mask: u32 = 0;
        for (words) |w| {
            const v = w.v & keep(w.k);
            if (self.shadow[w.k] == v) continue;
            self.shadow[w.k] = v;
            mask |= @as(u32, 1) << w.k;
            self.put(w.v);
        }
        if (mask == 0 and cmd == hw.BLIT_CMD_NOP) {
            self.n = at; // nothing to set: no descriptor
            return;
        }
        self.reg(hw.OFF_BLIT_QUEUE + 4 * (self.half * HALF + at)).* = mask | @as(u32, cmd) << 24;
    }

    pub fn set(self: *Queue, words: []const Word) void {
        self.op(hw.BLIT_CMD_NOP, words);
    }

    /// A plain FILL (no halftone, CON2 cleared) of [x, x+w) x [y, y+h) on the
    /// destination the list holds (set() words 8 and 9, or the block's).
    pub fn fill(self: *Queue, x: u16, y: u16, w: u16, h: u16, color: u8) void {
        self.op(hw.BLIT_CMD_FILL, &.{
            .{ .k = 1, .v = color },
            .{ .k = 10, .v = @as(u32, w) | @as(u32, h) << 16 },
            .{ .k = 11, .v = @as(u32, x) | @as(u32, y) << 16 },
        });
    }

    /// Run the list built so far (the board returns at once; the next kick, a
    /// flush or any machine call waits for it). The next list goes in the other half.
    pub fn kick(self: *Queue) void {
        if (self.n == 0) return;
        self.reg(hw.BLIT_Q_START).* = @intCast(self.half * HALF | self.n << 16);
        self.blit(hw.BLIT_CMD_QUEUE);
        self.half ^= 1;
        self.n = 0;
        self.pending = true;
    }

    /// kick(), then wait: every op queued before this has drawn.
    pub fn flush(self: *Queue) void {
        self.kick();
        if (!self.pending) return;
        self.blit(hw.BLIT_CMD_NOP); // the board's hwBlit waits for the list first
        self.pending = false;
    }

    // hwBlit() with COMMAND = cmd, COMMAND then put back as the cart left it.
    fn blit(self: *Queue, cmd: u8) void {
        const p: *volatile u8 = @ptrFromInt(self.base + hw.BLIT_COMMAND);
        const was = p.*;
        p.* = cmd;
        hw.hwBlit();
        p.* = was;
    }
};
