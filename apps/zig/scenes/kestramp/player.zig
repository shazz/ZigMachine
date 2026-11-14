// --------------------------------------------------------------------------
// KESTRAMP: the player under the window: C:\MUSIC's list, one stream on the
// sound side (mp3_player/stream.zig, unchanged), the track order, the
// selection and the title. The cart's keys and pointer (kestramp.zig) call
// these; the window (panel.zig) only reads the result.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const List = @import("../mp3_player/list.zig").List;
const Stream = @import("../mp3_player/stream.zig").Stream;
const id3 = @import("../mp3_player/id3.zig");
const Order = @import("order.zig").Order;
const panel = @import("panel.zig");
const lcd = @import("lcd.zig");

const SCROLL_EVERY: u32 = 4; // frames per pixel of the title's scroll

pub const Player = struct {
    list: List,
    stream: Stream,
    order: Order,
    sel: usize,
    top: usize,
    playing: ?usize,
    title_buf: [40]u8,
    title_len: usize,
    title_gen: u32,
    scroll: u32,
    tick: u32,
    ok: bool,

    pub fn init(self: *Player) void {
        self.list.n = 0;
        self.stream = .{};
        self.order = .{};
        self.sel = 0;
        self.top = 0;
        self.playing = null;
        self.title_len = 0;
        self.title_gen = 0;
        self.scroll = 0;
        self.tick = 0;
        self.ok = self.stream.alloc();
        self.list.scan();
    }

    /// Play the selection, or resume a pause.
    pub fn play(self: *Player) void {
        if (self.playing != null and self.stream.state() & 3 == 2) return self.pause();
        self.start(self.sel);
    }

    /// Toggles pause: arg 1 pauses a playing stream, 0 resumes a paused one.
    pub fn pause(self: *Player) void {
        if (self.playing == null) return;
        zg.mp3Ctl(.pause, @intFromBool(self.stream.state() & 3 == 1));
    }

    pub fn stop(self: *Player) void {
        self.stream.close();
        self.playing = null;
        self.title_len = 0;
        self.title_gen +%= 1;
    }

    /// Next or previous in the order. Stopped, the selection moves instead (no track to step from).
    pub fn skip(self: *Player, forward: bool) void {
        const at = self.playing orelse return self.moveSel(if (forward) 1 else -1);
        const to = if (forward) self.order.next(self.list.n, at) else self.order.prev(self.list.n, at);
        const i = to orelse return self.stop();
        self.start(i);
    }

    pub fn start(self: *Player, i: usize) void {
        if (!self.ok or i >= self.list.n) return;
        var buf: [32]u8 = undefined;
        if (!self.stream.open(self.list.path(i, &buf))) return self.stop();
        self.playing = i;
        self.sel = i;
        self.moveSel(0);
        self.order.markStarted(i);
        self.setTitle(i);
        self.scroll = 0;
    }

    pub fn moveSel(self: *Player, d: i32) void {
        if (self.list.n == 0) return;
        const n: i32 = @intCast(self.list.n);
        self.sel = @intCast(@mod(@as(i32, @intCast(self.sel)) + d, n));
        if (self.sel < self.top) self.top = self.sel;
        if (self.sel >= self.top + panel.ROWS) self.top = self.sel + 1 - panel.ROWS;
    }

    /// Once a frame while a track is on: feed the stream, move the title, and go on when a track ends.
    pub fn update(self: *Player) void {
        if (self.playing == null) return;
        self.stream.pump();
        self.tick +%= 1;
        if (self.tick % SCROLL_EVERY == 0 and self.title_len * 8 > lcd.TITLE_W) self.scroll +%= 1;
        if (self.stream.state() & 3 == 3) self.skip(true); // ended: the next track, or stop after the last
    }

    /// The status word's meaning for the window (nosound: the player is not there).
    pub fn status(self: *const Player, word: u32) panel.Status {
        if (self.playing == null) return .stopped;
        if (word == 0) return .nosound;
        return if (word & 3 == 2) .paused else .playing;
    }

    fn setTitle(self: *Player, i: usize) void {
        const t = id3.title(self.stream.first(), &self.title_buf);
        self.title_len = if (t.len > 0) t.len else blk: {
            const name = self.list.items[i].slice();
            const n = @min(name.len, self.title_buf.len);
            @memcpy(self.title_buf[0..n], name[0..n]);
            break :blk n;
        };
        self.title_gen +%= 1;
    }
};
