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
// Each list runs on a working copy of the register block taken at its kick;
// the queue never writes the block, so the block, and any other code driving
// the blitter, is left alone. The words set() and the ops gave are kept from list to list,
// across auto-kicks and flushes (effects/blit_list.zig): a later op sees them
// whatever the block holds; the words the queue never set are the block's.
//
// Order: the queue's ops run at their kick. A direct hwBlit() made while a list
// is being built runs BEFORE that list's ops (on both machines): flush() first.
// --------------------------------------------------------------------------
const hw = @import("hardware");
const list = @import("effects/blit_list.zig");

pub const HALF: usize = hw.BLIT_QUEUE_WORDS / 2; // a list's room: the other half may still be running
pub const Word = list.Word;

pub const Queue = struct {
    base: usize = 0, // the video region (hwVideoBase)
    l: list.List = undefined,
    pending: bool = false, // a list was kicked and not yet waited for

    pub fn init(self: *Queue, base: usize) void {
        self.* = .{ .base = base, .l = .{
            .ring = @ptrFromInt(base + hw.OFF_BLIT_QUEUE),
            .block = @ptrFromInt(base + hw.OFF_BLIT),
            .half = HALF,
        } };
    }

    /// One op: COMMAND `cmd` (NOP: only set the words) after `words`, which must
    /// come in rising k and stay the queue's for the ops after it.
    pub fn op(self: *Queue, cmd: u8, words: []const Word) void {
        if (!self.l.fits(words.len)) self.kick();
        self.l.op(cmd, words);
    }

    pub fn set(self: *Queue, words: []const Word) void {
        self.op(hw.BLIT_CMD_NOP, words);
    }

    /// A plain FILL (no halftone, CON2 cleared) of [x, x+w) x [y, y+h) on the
    /// destination the queue holds (set() words 8 and 9, or the block's): a
    /// header and three words, ~4 posted stores, the hot path of a polygon filler.
    pub inline fn fill(self: *Queue, x: u16, y: u16, w: u16, h: u16, color: u8) void {
        if (!self.l.fits(3)) self.kick();
        const hdr: u32 = @as(u32, hw.BLIT_CMD_FILL) << 24 | 1 << 1 | 1 << 10 | 1 << 11;
        self.l.whole3(hdr, color, @as(u32, w) | @as(u32, h) << 16, @as(u32, x) | @as(u32, y) << 16);
    }

    /// Run the list built so far (the board returns at once; the next kick, a
    /// flush or any machine call waits for it). The next list goes in the other half.
    pub fn kick(self: *Queue) void {
        const r = self.l.close() orelse return;
        const q: *volatile u32 = @ptrFromInt(self.base + hw.BLIT_Q_START);
        q.* = @intCast(r.start | r.count << 16);
        self.blit(hw.BLIT_CMD_QUEUE);
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
