//! zigdemo ring: a part's BIG file read IN ORDER through a ring, for a file the assets arena cannot
//! hold (a point cloud, a long animation): the part reads it while it plays, never the whole of it.
//! The file is a header (`cfg.header_len` bytes, parsed by the demo's `parse`) then records, each
//! starting with its length as a little-endian u32 (the length counts itself). The header length
//! and every record start at a multiple of 4 (so a length word never straddles the ring's end).
//! The ring (RING bytes, a multiple of `cfg.chunk`) takes `chunk`-byte reads at the file's absolute
//! offsets (offset % RING); a record that runs past the ring's end gets its wrapped head copied
//! after it (the SPILL, `cfg.spill` bytes past the ring), so a record is always one contiguous slice.
//! Nothing before `head` (the record still in use) is overwritten; the part moves `head` with
//! release(). A seek back = open() again. Over the same `Files` contract as zigdemo.assets
//! (open / read / close); a read shorter than asked is the end of the file (GEMDOS Fread).

pub const Config = struct {
    chunk: u32 = 32 * 1024, // one read (one C: round trip on KESTREL, ~0.5 ms)
    spill: u32 = 32 * 1024, // the biggest record that may wrap (the converter checks it)
    header_len: u32 = 0,
    min_record: u32 = 4, // a record is at least its length word (the demo may ask for more)
};

/// `parse(bytes, ring)`: the header from the file's first `header_len` bytes, null = not this file.
pub fn Ring(comptime F: type, comptime cfg: Config, comptime Header: type, comptime parse: fn ([]const u8, u32) ?Header) type {
    return struct {
        const Self = @This();
        pub const CHUNK = cfg.chunk;
        pub const SPILL = cfg.spill;
        files: *F,
        buf: []align(8) u8, // ring + SPILL
        ring: u32,
        h: i32 = -1,
        head: u32 = 0, // absolute: the first byte still needed
        tail: u32 = 0, // absolute: the bytes read so far
        eof: bool = false,
        failed: bool = false,
        hdr: ?Header = null,

        pub fn open(self: *Self, path: []const u8) void {
            if (self.h >= 0) self.files.close(self.h);
            self.* = .{ .files = self.files, .buf = self.buf, .ring = self.ring };
            self.h = self.files.open(path);
            if (self.h < 0) self.failed = true;
        }

        pub fn close(self: *Self) void {
            if (self.h >= 0) self.files.close(self.h);
            self.h = -1;
        }

        /// Up to `reads` chunk reads while there is room ahead of `head`; the header once it is in.
        pub fn fill(self: *Self, reads: u32) void {
            var n: u32 = 0;
            while (n < reads and self.h >= 0 and !self.eof) : (n += 1) {
                const pos = self.tail % self.ring;
                const len = @min(CHUNK, self.ring - pos);
                if (self.tail - self.head + len > self.ring) break;
                const got = self.files.read(self.h, self.buf[pos..][0..len]);
                if (got < 0) {
                    self.failed = true;
                    return;
                }
                self.tail += @intCast(got);
                if (got < len) self.eof = true;
            }
            if (self.hdr == null and self.tail >= cfg.header_len) self.header();
        }

        fn header(self: *Self) void {
            self.hdr = parse(self.buf[0..cfg.header_len], self.ring) orelse {
                self.failed = true;
                return;
            };
            self.head = cfg.header_len;
        }

        /// The record at absolute offset `at` as one slice, or null while it is not all in.
        pub fn record(self: *Self, at: u32) ?[]const u8 {
            if (at + cfg.min_record > self.tail) return null;
            const pos = at % self.ring;
            const len = rd(self.buf, pos);
            if (len < cfg.min_record or len > @max(SPILL, self.ring - cfg.header_len)) {
                self.failed = true;
                return null;
            }
            if (at + len > self.tail) return null;
            if (pos + len > self.ring) { // wrapped: its head is at the ring's start
                const over = pos + len - self.ring;
                @memcpy(self.buf[self.ring..][0..over], self.buf[0..over]);
            }
            return self.buf[pos..][0..len];
        }

        /// The bytes before `at` may be read over.
        pub fn release(self: *Self, at: u32) void {
            self.head = at;
        }
    };
}

fn rd(b: []const u8, at: usize) u32 {
    return @as(u32, b[at]) | @as(u32, b[at + 1]) << 8 | @as(u32, b[at + 2]) << 16 | @as(u32, b[at + 3]) << 24;
}
