// --------------------------------------------------------------------------
// MP3 PLAYER (a tools cart): a jukebox for the .MP3 files in C:\MUSIC, the SD
// card's /HD/MUSIC on the board (KOS GEMDOS: Fsfirst / Fsnext for the list,
// Fopen / Fread in 32 KiB chunks). The cart only reads and feeds: the sound
// side decodes (zg.mp3Ctl / mp3Feed / mp3Status, libs/zig/players/mp3.zig:
// pvmp3 on BARD, or in the page's AudioWorklet) onto the four Paula channels,
// so no Paula sound effect plays meanwhile.
//
// Keys: Up / Down pick, Return or Space play, P pause, N / B (or Right / Left)
// next / previous, Esc stop, Esc again back to the OS. A track that ends plays
// the next. The screen shows the title (the ID3v2 TIT2, else the file name),
// the time (frames decoded x 1152 / rate), the rate, and BARD's load (the
// board's sound CPU; "--" where nothing measures one).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const List = @import("mp3_player/list.zig").List;
const Stream = @import("mp3_player/stream.zig").Stream;
const view = @import("mp3_player/view.zig");
const id3 = @import("mp3_player/id3.zig");

const K_ESC: u32 = 0xE012; // docs/sealed-loader.js KEY_CODES
const RATES = [_]u32{ 0, 32000, 44100, 48000, 0 };

pub const Demo = struct {
    list: List,
    stream: Stream,
    sel: usize,
    top: usize,
    playing: ?usize,
    title_buf: [40]u8,
    title_len: usize,
    quit: bool,
    shown: ?view.Shown,
    ok: bool,

    pub fn init(self: *Demo, os: *ZigOS) void {
        self.list.n = 0;
        self.stream = .{};
        self.sel = 0;
        self.top = 0;
        self.playing = null;
        self.title_len = 0;
        self.quit = false;
        self.shown = null;
        self.ok = self.stream.alloc();
        view.palette(os);
        self.list.scan();
    }

    pub fn ownsKeyboard(self: *Demo) u32 {
        _ = self;
        return 1; // Space plays, Esc stops: the cart's, not the host's
    }

    /// The host's swap protocol (demo_main.zig): 4 = back to the OS.
    pub fn pollCart(self: *Demo) i32 {
        return if (self.quit) 4 else 0;
    }

    pub fn input(self: *Demo, dir: u32) void {
        switch (dir) {
            0 => self.move(-1),
            1 => self.move(1),
            2 => self.skip(-1),
            3 => self.skip(1),
            else => {},
        }
    }

    pub fn key(self: *Demo, cp: u32) void {
        switch (cp) {
            13, ' ' => self.start(self.sel),
            'p', 'P' => if (self.playing != null) zg.mp3Ctl(.pause, @intFromBool(self.stream.state() & 3 == 1)),
            'n', 'N' => self.skip(1),
            'b', 'B' => self.skip(-1),
            'r', 'R' => if (self.playing == null) self.list.scan(),
            K_ESC => if (self.playing != null) self.stop() else {
                self.quit = true;
            },
            else => {},
        }
    }

    pub fn update(self: *Demo, os: *ZigOS, dt: f32) void {
        _ = os;
        _ = dt;
        if (self.playing == null) return;
        self.stream.pump();
        if (self.stream.state() & 3 == 3) self.skip(1); // ended: the next track, or stop after the last
    }

    pub fn render(self: *Demo, os: *ZigOS, dt: f32) void {
        _ = dt;
        const word = if (self.playing != null) self.stream.state() else 0;
        const rate = RATES[@min((word >> 4) & 15, 4)];
        const s = view.Shown{
            .sel = self.sel,
            .top = self.top,
            .playing = self.playing,
            .word = word & 0x1FF, // not the counters: an underrun is not a redraw
            .secs = if (rate == 0) 0 else @intCast(@as(u64, zg.mp3Status(.frames)) * 1152 / rate),
            .load = zg.mp3Status(.load) / 10 * 10, // to 1 %: a redraw a second at most
            .n = self.list.n,
        };
        if (self.shown) |old| if (std.meta.eql(old, s)) return;
        self.shown = s;
        view.draw(os, s, &self.list, self.title_buf[0..self.title_len]);
    }

    fn move(self: *Demo, d: i32) void {
        if (self.list.n == 0) return;
        const n: i32 = @intCast(self.list.n);
        self.sel = @intCast(@mod(@as(i32, @intCast(self.sel)) + d, n));
        if (self.sel < self.top) self.top = self.sel;
        if (self.sel >= self.top + view.ROWS) self.top = self.sel + 1 - view.ROWS;
    }

    fn skip(self: *Demo, d: i32) void {
        const at = self.playing orelse return;
        const next = @as(i32, @intCast(at)) + d;
        if (next < 0 or next >= @as(i32, @intCast(self.list.n))) return self.stop();
        self.start(@intCast(next));
    }

    fn start(self: *Demo, i: usize) void {
        if (!self.ok or i >= self.list.n) return;
        var buf: [32]u8 = undefined;
        if (!self.stream.open(self.list.path(i, &buf))) return self.stop();
        self.playing = i;
        self.sel = i;
        self.move(0);
        const t = id3.title(self.stream.first(), &self.title_buf);
        const name = self.list.items[i].slice();
        self.title_len = if (t.len > 0) t.len else blk: {
            @memcpy(self.title_buf[0..name.len], name);
            break :blk name.len;
        };
    }

    fn stop(self: *Demo) void {
        self.stream.close();
        self.playing = null;
        self.title_len = 0;
    }
};
