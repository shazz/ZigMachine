// --------------------------------------------------------------------------
// BAD APPLE!! the LOCAL MP3 song (-Dbadapple_mp3): SONG.MP3 on the floppy next to the film, streamed into the
// sound side's MP3 player (zg.mp3Ctl / mp3Feed / mp3Status, libs/zig/players/mp3.zig) a 32 KiB disk read at a
// time, fed as the player's 64 KiB ring has room (the flow control of apps/zig/scenes/mp3_player/stream.zig:
// the cart knows what it fed, the player says what it used; for TRUST frames after the start the status may
// still be stale, so the player is assumed to have used nothing). Its position (frames decoded x the frame
// size read off the file, mp3clock.zig) is the film's clock. Compiled in only with the option: the public
// cart has no MP3 import at all.
// The player is STARTED on the first pump, never in init: on the board the cart's init runs before the sound
// side is up (fpga/cycles/bmain.c: host_boot_cart, then baudio_boot), and a start or feed made then is dropped
// (fpga/host/audio_bridge.c), so the MP3 stayed idle for good (board, 27 Nov).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blocks = @import("blocks.zig");
const mp3clock = @import("mp3clock.zig");

pub const FILE = "SONG.MP3";
const CHUNK: u32 = 32 * 1024;
const TRUST: u32 = 4;

pub const Song = struct {
    disk: blocks.DiskFile,
    format: mp3clock.Format,
    buf: []u8,
    have: u32 = 0, // bytes in buf
    sent: u32 = 0, // of them fed
    fed: u32 = 0, // since the start
    age: u32 = 0, // frames since the start
    ended: bool = false,
    started: bool = false, // mp3Ctl(.start) sent (on the first pump)

    /// Finds SONG.MP3 and reads its first chunk and its format; null without a readable song. The player is started
    /// by the first pump (from the cart's update, once the sound side is up).
    pub fn open() ?Song {
        var s: Song = .{
            .disk = blocks.DiskFile.find(FILE) orelse return null,
            .format = undefined,
            .buf = zg.mem.mustAlloc(u8, CHUNK),
        };
        if (!s.read()) return null;
        s.format = mp3clock.parse(s.buf[0..s.have]) orelse return null;
        return s;
    }

    /// Once a frame: feed what fits, read the next chunk when this one is spent, tell the player at the end.
    pub fn pump(self: *Song) void {
        if (!self.started) {
            zg.mp3Ctl(.start, 0);
            self.started = true;
            self.age = 0;
        }
        self.age +|= 1;
        if (self.sent < self.have) {
            const n = @min(self.have - self.sent, self.room(), zg.MP3_FEED_MAX);
            if (n == 0) return;
            zg.mp3Feed(self.buf[self.sent .. self.sent + n]);
            self.sent += n;
            self.fed +%= n;
        } else if (self.disk.left() > 0) {
            if (!self.read()) self.finish(); // a short disk read: play out what was fed
        } else self.finish();
    }

    /// Microseconds of song decoded so far; null while the status cannot be trusted yet or nothing has played.
    pub fn position(self: *const Song) ?u64 {
        if (self.age <= TRUST) return null;
        const frames = zg.mp3Status(.frames);
        return if (frames == 0) null else self.format.us(frames);
    }

    fn finish(self: *Song) void {
        if (self.ended) return;
        zg.mp3Ctl(.end, 0);
        self.ended = true;
    }

    fn read(self: *Song) bool {
        const n = @min(self.disk.left(), CHUNK);
        self.sent = 0;
        self.have = 0;
        if (n == 0 or !self.disk.read(self.buf[0..n])) return false;
        self.have = n;
        return true;
    }

    /// Bytes the player's ring can take now.
    fn room(self: *const Song) u32 {
        const used: u32 = if (self.age <= TRUST) 0 else zg.mp3Status(.used);
        const fill = self.fed -% used;
        return if (fill > zg.MP3_RING) zg.MP3_RING - @min(self.fed, zg.MP3_RING) else zg.MP3_RING - fill;
    }
};
