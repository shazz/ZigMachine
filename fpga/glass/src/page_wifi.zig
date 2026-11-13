// The Wi-Fi page (console > Wi-Fi...): the board's network, picked and joined from the OSD.
// Pure state and keys, as page_console.zig; page_wifi_draw.zig draws it, app_wifi.zig runs the
// jobs and fills `info` / `nets` from their results. Four screens:
//
//   home      the state (network, address, the card's saved one), then Scan, Forget, Back
//   list      the networks a scan saw, strongest first: '*' secured, signal bars, the SSID
//   password  the key typed on the keyboard, shown as '*' only; Enter joins
//   busy      a job runs (a scan, a join: up to 20 s); Esc leaves, the job goes on
const std = @import("std");
const map = @import("map.zig");
const osd = @import("osd.zig");
const wc = @import("wifi_conf.zig");
const wp = @import("wifi_parse.zig");
const job = @import("wifi_job.zig");
const cmd = @import("wifi_cmd.zig");

pub const Screen = enum { home, list, password, busy };
pub const Item = enum { scan, forget, back };
pub const ITEMS = std.enums.values(Item);
/// What a key asks app_wifi.zig to do (menu.Action.wifi), or `back` to the console page.
pub const Key = enum { none, back, scan, join, forget };
/// The job menu.Action.wifi starts.
pub const Cmd = job.Kind;
pub const SHOWN = osd.ROWS - 2; // list rows 1..14

/// The state the last job left (app_wifi.zig), and the card's saved network.
pub const Info = struct {
    known: bool = false, // a job has answered since the page opened
    fail: job.Fail = .none,
    missing: ?cmd.Tool = null,
    connected: ?wc.Ssid = null,
    ip_buf: [15]u8 = undefined,
    ip_len: u8 = 0,
    saved: ?wc.Saved = null,

    pub fn ip(self: *const Info) []const u8 {
        return self.ip_buf[0..self.ip_len];
    }
};

pub const State = struct {
    screen: Screen = .home,
    cursor: usize = 0, // home's item
    pick: usize = 0, // the list's selected network
    top: usize = 0,
    busy_what: job.Kind = .status,
    phase: usize = 0, // the busy screen's spinner, advanced by the app's tick
    info: Info = .{},
    nets: [wp.NETS_MAX]wp.Net = undefined,
    n_nets: usize = 0,
    pass: [wc.PASS_MAX + 1]u8 = undefined,
    pass_len: u8 = 0,
    short: bool = false, // Enter on a password WPA2 refuses: the screen says so

    pub fn key(self: *State, code: u32) Key {
        return switch (self.screen) {
            .home => self.homeKey(code),
            .list => self.listKey(code),
            .password => self.passKey(code),
            .busy => if (code == map.KEY_ESCAPE or code == map.KEY_BACKSPACE) .back else .none,
        };
    }

    fn homeKey(self: *State, code: u32) Key {
        switch (code) {
            map.KEY_ARROW_UP => self.cursor -|= 1,
            map.KEY_ARROW_DOWN => self.cursor = @min(self.cursor + 1, ITEMS.len - 1),
            map.KEY_ESCAPE, map.KEY_BACKSPACE, map.KEY_ARROW_LEFT => return .back,
            map.KEY_ENTER, ' ' => return switch (ITEMS[self.cursor]) {
                .scan => .scan,
                .forget => .forget,
                .back => .back,
            },
            else => {},
        }
        return .none;
    }

    fn listKey(self: *State, code: u32) Key {
        switch (code) {
            map.KEY_ARROW_UP => self.pick -|= 1,
            map.KEY_ARROW_DOWN => self.pick = @min(self.pick + 1, self.n_nets -| 1),
            map.KEY_PAGE_UP => self.pick -|= SHOWN,
            map.KEY_PAGE_DOWN => self.pick = @min(self.pick + SHOWN, self.n_nets -| 1),
            map.KEY_ESCAPE, map.KEY_BACKSPACE, map.KEY_ARROW_LEFT => self.screen = .home,
            'r', 'R' => return .scan,
            map.KEY_ENTER, ' ' => {
                if (self.n_nets == 0) return .none;
                if (!self.nets[self.pick].secured) return .join;
                self.clearPass();
                self.screen = .password;
            },
            else => {},
        }
        if (self.pick < self.top) self.top = self.pick;
        if (self.pick >= self.top + SHOWN) self.top = self.pick + 1 - SHOWN;
        return .none;
    }

    /// Every printable key is the password's: no letter is a shortcut here.
    fn passKey(self: *State, code: u32) Key {
        switch (code) {
            map.KEY_ESCAPE => {
                self.clearPass();
                self.screen = .list;
            },
            map.KEY_BACKSPACE => {
                self.pass_len -|= 1;
                self.pass[self.pass_len] = 0;
            },
            map.KEY_ENTER => {
                if (wc.validPass(self.passText())) return .join;
                self.short = true;
            },
            0x20...0x7E => if (self.pass_len < wc.PASS_MAX) {
                self.pass[self.pass_len] = @intCast(code);
                self.pass_len += 1;
                self.short = false;
            },
            else => {},
        }
        return .none;
    }

    pub fn passText(self: *const State) []const u8 {
        return self.pass[0..self.pass_len];
    }

    pub fn clearPass(self: *State) void {
        std.crypto.secureZero(u8, &self.pass);
        self.pass_len = 0;
        self.short = false;
    }

    /// The network Enter picked in the list.
    pub fn picked(self: *const State) ?wp.Net {
        return if (self.pick < self.n_nets) self.nets[self.pick] else null;
    }

    /// A job started: the busy screen until its result lands (app_wifi.zig).
    pub fn wait(self: *State, what: job.Kind) void {
        self.busy_what = what;
        self.screen = .busy;
    }

    /// The page opened from the console: home, the cursor on Scan, the state to be read.
    pub fn open(self: *State) void {
        self.clearPass();
        self.screen = .home;
        self.cursor = 0;
        self.info.known = false;
    }
};

/// An SSID as the OSD can show it: bytes outside printable ASCII (UTF-8, control) as '?'.
pub fn shown(buf: []u8, ssid: []const u8) []const u8 {
    const n = @min(buf.len, ssid.len);
    for (buf[0..n], ssid[0..n]) |*o, c| o.* = if (c >= 0x20 and c <= 0x7E) c else '?';
    return buf[0..n];
}
