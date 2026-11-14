// --------------------------------------------------------------------------
// MP3 PLAYER: one file streamed into the sound side's MP3 player (zg.mp3Ctl /
// mp3Feed / mp3Status, libs/zig/players/mp3.zig). The file is read off C: a
// 32 KiB Fread at a time (~0.5 ms on the board, one every 1-2 s of music) and
// fed as the player's 64 KiB ring has room: the cart knows what it fed, the
// player says what it used, the difference is the fill. The status answers a
// frame or two late, so for TRUST frames after a start the cart assumes the
// player used nothing (and that it has not ended): it never overfeeds.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const gemdos = @import("kos_gemdos");

pub const CHUNK: u32 = 32 * 1024;
const TRUST: u32 = 4;

pub const Stream = struct {
    buf: []u8 = &.{},
    h: i32 = -1,
    have: u32 = 0, // bytes in buf
    sent: u32 = 0, // of them fed
    fed: u32 = 0, // since the start
    eof: bool = false,
    age: u32 = 0, // frames since the start
    ended: bool = false, // the player was told the input ended
    live: bool = false, // a stream is on (open .. close)

    pub fn alloc(self: *Stream) bool {
        self.buf = zg.mem.alloc(u8, CHUNK) orelse return false;
        return true;
    }

    /// Open `path` and start a fresh stream on it; false if it cannot be read.
    pub fn open(self: *Stream, path: []const u8) bool {
        self.close();
        const dos = gemdos.dos();
        const h = dos.Fopen(path, 0);
        if (h < 0) return false;
        self.h = h;
        self.fed = 0;
        self.sent = 0;
        self.eof = false;
        self.age = 0;
        self.have = 0;
        self.ended = false;
        self.live = true;
        zg.mp3Ctl(.start, 0);
        self.read(); // the first chunk: the caller reads the title off it (first())
        return true;
    }

    pub fn close(self: *Stream) void {
        if (self.h >= 0) _ = gemdos.dos().Fclose(self.h);
        if (self.live) zg.mp3Ctl(.stop, 0);
        self.h = -1;
        self.age = 0;
        self.live = false;
    }

    /// The file's first chunk, until the first feed (the ID3 tag is in it).
    pub fn first(self: *const Stream) []const u8 {
        return self.buf[0..self.have];
    }

    pub fn playing(self: *const Stream) bool {
        return self.live;
    }

    /// The player's status word, or "playing" while it may still be the last stream's.
    pub fn state(self: *const Stream) u32 {
        const w = zg.mp3Status(.word);
        return if (self.age <= TRUST) (w & ~@as(u32, 3)) | 1 else w;
    }

    /// MP3 frames decoded since this stream's start: 0 while the status may still be the last stream's.
    pub fn decoded(self: *const Stream) u32 {
        return if (!self.live or self.age <= TRUST) 0 else zg.mp3Status(.frames);
    }

    /// Once a frame: feed what fits, read the next chunk when this one is spent.
    pub fn pump(self: *Stream) void {
        if (!self.live) return;
        self.age +|= 1;
        if (self.sent < self.have) {
            const n = @min(self.have - self.sent, self.room(), zg.MP3_FEED_MAX);
            if (n == 0) return;
            zg.mp3Feed(self.buf[self.sent .. self.sent + n]);
            self.sent += n;
            self.fed +%= n;
        } else if (!self.eof and self.h >= 0) {
            self.read();
        } else if (self.eof and !self.ended) {
            zg.mp3Ctl(.end, 0); // all fed: the player plays out what it holds
            self.ended = true;
        }
    }

    fn read(self: *Stream) void {
        const r = gemdos.dos().Fread(self.h, @intCast(CHUNK), self.buf.ptr);
        self.sent = 0;
        self.have = if (r > 0) @intCast(r) else 0;
        if (r < @as(i32, @intCast(CHUNK))) { // the file's end (or an error): the player plays out what it has
            self.eof = true;
            _ = gemdos.dos().Fclose(self.h);
            self.h = -1;
        }
    }

    /// Bytes the player's ring can take now.
    fn room(self: *const Stream) u32 {
        const used: u32 = if (self.age <= TRUST) 0 else zg.mp3Status(.used);
        const fill = self.fed -% used;
        return if (fill > zg.MP3_RING) zg.MP3_RING - @min(self.fed, zg.MP3_RING) else zg.MP3_RING - fill;
    }
};
