// --------------------------------------------------------------------------
// KESTRAMP: a classic late-90s desktop MP3 player's main window, for the .MP3
// files in C:\MUSIC. The sound side decodes (zg.mp3Ctl / mp3Feed / mp3Status,
// libs/zig/players/mp3.zig); the file reader, the list and the ID3 title are
// MP3 PLAYER's own modules (mp3_player/*.zig), used unchanged.
//
// Reference, for the layout and the controls only: Webamp,
// https://github.com/captbaritone/webamp, MIT licence (its README: "released
// under the MIT License"). No skin, artwork, logo or code of it is used; the
// window, its digits and its logo are drawn here.
//
// Not in this cart, because the MP3 API has no such thing: volume, balance,
// kbps (no bitrate), the remaining time (no duration) and seeking. The bar
// shows the bytes the player has used of the file: display only.
//
// Keys: Z prev, X play (resumes a pause), C or Space pause, V stop, B next,
// L open the list (Up / Down move in it, Return plays its row), S shuffle,
// R repeat, Left / Right prev / next, Esc stops and leaves the cart.
//
// Files: layout.zig (geometry), panel.zig (the window), lcd.zig, list_view.zig,
// hit.zig (presses), player.zig (the list, the stream, the order), order.zig.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Player = @import("kestramp/player.zig").Player;
const panel = @import("kestramp/panel.zig");
const hit = @import("kestramp/hit.zig");

const K_ESC: u32 = 0xE012; // docs/sealed-loader.js KEY_CODES
const RATES = [_]u32{ 0, 320, 441, 480, 0 }; // the status word's rate code, in tenths of a kHz

pub const Demo = struct {
    p: Player,
    list_open: bool,
    quit: bool,
    btn_down: bool,
    shown: ?panel.Shown,

    pub fn init(self: *Demo, os: *ZigOS) void {
        self.p.init();
        self.list_open = false;
        self.quit = false;
        self.btn_down = false;
        self.shown = null;
        panel.palette(os);
    }

    pub fn ownsKeyboard(self: *Demo) u32 {
        _ = self;
        return 1; // the keys are the cart's: Esc leaves it, not the host
    }

    /// The host's swap protocol (demo_main.zig): 4 = back to the OS.
    pub fn pollCart(self: *Demo) i32 {
        return if (self.quit) 4 else 0;
    }

    pub fn input(self: *Demo, dir: u32) void {
        switch (dir) {
            0 => if (self.list_open) self.p.moveSel(-1),
            1 => if (self.list_open) self.p.moveSel(1),
            2 => self.p.skip(false),
            3 => self.p.skip(true),
            else => {},
        }
    }

    pub fn key(self: *Demo, cp: u32) void {
        switch (cp) {
            13 => self.p.start(self.p.sel),
            ' ', 'c', 'C' => self.p.pause(),
            'x', 'X' => self.p.play(),
            'v', 'V' => self.p.stop(),
            'z', 'Z' => self.p.skip(false),
            'b', 'B' => self.p.skip(true),
            'l', 'L' => self.list_open = !self.list_open,
            's', 'S' => self.p.order.shuffle = !self.p.order.shuffle,
            'r', 'R' => self.p.order.repeat = !self.p.order.repeat,
            K_ESC => self.leave(),
            else => {},
        }
    }

    /// A press (the left button's edge) on a button, a toggle or a list row. The page's
    /// double-click pulse (bit 1) is not a press.
    pub fn pointer(self: *Demo, x: i32, y: i32, buttons: u32) void {
        const down = buttons & 1 != 0;
        const edge = down and !self.btn_down;
        self.btn_down = down;
        if (!edge or buttons & 2 != 0) return;
        const h = hit.hitTest(x, y, self.list_open, self.p.list.n, self.p.top) orelse return;
        switch (h) {
            .btn => |b| self.button(b),
            .toggle => |t| self.toggle(t),
            .row => |i| self.p.start(i),
        }
    }

    pub fn update(self: *Demo, os: *ZigOS, dt: f32) void {
        _ = os;
        _ = dt;
        self.p.update();
    }

    pub fn render(self: *Demo, os: *ZigOS, dt: f32) void {
        _ = dt;
        const s = self.snapshot();
        panel.redraw(os, self.shown, s, self.p.title_buf[0..self.p.title_len], &self.p.list);
        self.shown = s;
    }

    fn snapshot(self: *Demo) panel.Shown {
        const word = if (self.p.playing != null) self.p.stream.state() else 0;
        const rate = RATES[@min((word >> 4) & 15, 4)];
        const secs: u32 = if (rate == 0) 0 else @intCast(@as(u64, zg.mp3Status(.frames)) * 1152 * 10 / rate);
        const size: u32 = if (self.p.playing) |i| self.p.list.items[i].size else 0;
        const st = self.p.status(word);
        return .{
            .secs = secs,
            .rate = rate,
            .stereo = word & 0x100 != 0,
            .title_gen = self.p.title_gen,
            .scroll = self.p.scroll,
            .pos = panel.barPixels(zg.mp3Status(.used), size),
            .status = st,
            .track = if (self.p.playing) |i| i + 1 else 0,
            .n = self.p.list.n,
            .buttons = buttonMask(st, self.list_open),
            .toggles = toggleMask(self.p.order),
            .list_open = self.list_open,
            .top = self.p.top,
            .sel = self.p.sel,
        };
    }

    fn button(self: *Demo, b: panel.Btn) void {
        switch (b) {
            .prev => self.p.skip(false),
            .play => self.p.play(),
            .pause => self.p.pause(),
            .stop => self.p.stop(),
            .next => self.p.skip(true),
            .open => self.list_open = !self.list_open,
        }
    }

    fn toggle(self: *Demo, t: u1) void {
        if (t == 0) self.p.order.shuffle = !self.p.order.shuffle else self.p.order.repeat = !self.p.order.repeat;
    }

    fn leave(self: *Demo) void {
        self.p.stop();
        self.quit = true;
    }
};

fn buttonMask(st: panel.Status, list_open: bool) u8 {
    var m: u8 = 0;
    if (st == .playing) m |= bit(.play);
    if (st == .paused) m |= bit(.pause);
    if (list_open) m |= bit(.open);
    return m;
}

fn toggleMask(o: @import("kestramp/order.zig").Order) u8 {
    return @as(u8, @intFromBool(o.shuffle)) | (@as(u8, @intFromBool(o.repeat)) << 1);
}

fn bit(b: panel.Btn) u8 {
    return @as(u8, 1) << @intCast(@intFromEnum(b));
}
