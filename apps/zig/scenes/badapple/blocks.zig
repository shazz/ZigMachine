// --------------------------------------------------------------------------
// BAD APPLE!! the disk side: one 1 s ZX0 block at a time off the floppy, read AHEAD of the picture.
// Two raw buffers: the picture decodes from one while the next block is read (one disk call) and depacked
// a few KB a frame (zx0.Stream.step) into the other, so a block change costs a swap, not a ~1.5 Mc depack
// (the largest real block is 75 KB raw). If the picture catches up with the fill, takeBlock finishes it at once.
// Shared by the three carts (container.zig): each opens its own file with its own magic and buffer sizes.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const depackers = @import("depackers");
const container = @import("container.zig");

// Raw bytes depacked per pump. frame_cost measures ~170 cycles a byte on the real film's dense blocks (short matches), so
// 6 KB a pump was a ~1 Mc frame; 2 KB is ~0.35 Mc, and the largest block (76 KB) still fills in 38 of a block's 60 pumps.
pub const STEP: u32 = 2048;

pub const Slot = struct { raw: []u8, len: usize = 0, frames: u16 = 0 };

const Fill = enum { idle, depacking, ready, end, failed };

/// A file on the mounted floppy, read front to back.
pub const DiskFile = struct {
    file: zg.disk.Entry,
    pos: u32 = 0,

    pub fn find(name: []const u8) ?DiskFile {
        const lay = zg.disk.mount() orelse return null;
        return .{ .file = zg.disk.find(lay, name) orelse return null };
    }

    pub fn left(self: *const DiskFile) u32 {
        return self.file.len - self.pos;
    }

    /// Exactly dst.len bytes from the read position on, or false (past the end, or a short disk read).
    pub fn read(self: *DiskFile, dst: []u8) bool {
        if (@as(u64, self.pos) + dst.len > self.file.len) return false;
        const part = zg.disk.Entry{ .start = self.file.start + self.pos, .len = @intCast(dst.len), .kind = self.file.kind };
        if (zg.disk.read(part, dst) != dst.len) return false;
        self.pos += @intCast(dst.len);
        return true;
    }
};

pub const Loader = struct {
    disk: DiskFile,
    header: container.Header,
    next_block: u16 = 0,
    packed_buf: []u8,
    slots: [2]Slot,
    cur: u1 = 1, // the slot the picture decodes from; the other one is the fill target
    fill: Fill = .idle,
    stream: depackers.zx0.Stream = undefined,
    fill_frames: u16 = 0,

    /// Opens `name` on the mounted disk and reads its header (it must carry `magic`); null when the disk, the file
    /// or the header is bad. A block over `max_packed` / `max_raw` bytes (the format's limits) is refused when read.
    pub fn open(name: []const u8, magic: *const [4]u8, max_packed: usize, max_raw: usize) ?Loader {
        var l: Loader = .{
            .disk = DiskFile.find(name) orelse return null,
            .header = undefined,
            .packed_buf = zg.mem.mustAlloc(u8, max_packed),
            .slots = .{ .{ .raw = zg.mem.mustAlloc(u8, max_raw) }, .{ .raw = zg.mem.mustAlloc(u8, max_raw) } },
        };
        var hdr: [container.HEADER_SIZE]u8 = undefined;
        if (!l.disk.read(&hdr)) return null;
        l.header = container.parseHeader(&hdr, magic) orelse return null;
        return l;
    }

    /// Reads the next block header and its packed bytes and starts the depack into the fill slot.
    fn startFill(self: *Loader) void {
        if (self.next_block >= self.header.block_count) {
            self.fill = .end;
            return;
        }
        self.fill = .failed; // until every check below passes
        var bh_bytes: [container.BLOCK_HDR_SIZE]u8 = undefined;
        if (!self.disk.read(&bh_bytes)) return;
        const bh = container.parseBlockHeader(&bh_bytes) orelse return;
        if (bh.packed_len > self.packed_buf.len or bh.raw_len > self.slots[0].raw.len) return;
        if (!self.disk.read(self.packed_buf[0..bh.packed_len])) return;
        const dst = self.slots[self.cur ^ 1].raw[0..bh.raw_len];
        if (depackers.zx0.depackedLen(self.packed_buf[0..bh.packed_len]) != bh.raw_len) return;
        self.stream = depackers.zx0.Stream.init(self.packed_buf[0..bh.packed_len], dst) orelse return;
        self.fill_frames = bh.frame_count;
        self.fill = .depacking;
    }

    /// One slice of read-ahead work (call once a frame). False once the stream has failed.
    pub fn pump(self: *Loader, budget: u32) bool {
        if (self.fill == .idle) self.startFill();
        if (self.fill == .depacking) switch (self.stream.step(budget)) {
            .more => {},
            .done => {
                const s = &self.slots[self.cur ^ 1];
                s.len = self.stream.written();
                s.frames = self.fill_frames;
                self.next_block += 1;
                self.fill = .ready;
            },
            .failed => self.fill = .failed,
        };
        return self.fill != .failed;
    }

    /// The next block, ready to decode (the fill finished now if it was not yet); null at the end or on failure.
    pub fn takeBlock(self: *Loader) ?*const Slot {
        while (self.fill != .ready) {
            if (!self.pump(0xFFFF_FFFF) or self.fill == .end) return null;
        }
        self.cur ^= 1;
        self.fill = .idle;
        return &self.slots[self.cur];
    }
};
