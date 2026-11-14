// The Wi-Fi page drawn (page_wifi.zig has the state). Row 0 the title bar, rows 1..14 right of
// the section strip (30 wide), row 15 the status (menu.zig). The password is never drawn: one
// '*' a character, and only the count of them.
const std = @import("std");
const osd = @import("osd.zig");
const text = @import("text.zig");
const wp = @import("wifi_parse.zig");
const pw = @import("page_wifi.zig");

const W = osd.BODY_W;
const ITEM_ROW = 7;
const RULE = 10;
const HELP = 11;

const help = [_][]const u8{
    "Look for networks, pick one, type its password: Enter joins. Saved to wifi.conf once it works, as a hashed key.",
    "Delete wifi.conf from the card and leave the network: the board boots offline.",
    "Back to the console.",
};

pub fn draw(s: *const pw.State, o: *osd.Osd) void {
    switch (s.screen) {
        .home => home(s, o),
        .list => list(s, o),
        .password => password(s, o),
        .busy => busy(s, o),
    }
}

/// The status row's hint for the screen (menu.zig shows it while no message is set).
pub fn hint(s: *const pw.State) []const u8 {
    return switch (s.screen) {
        .home => "ENTER do  Up/Dn select  Esc",
        .list => "ENTER join  R rescan  Esc back",
        .password => "ENTER join  Esc cancel",
        .busy => "working...  Esc leave",
    };
}

fn row(o: *osd.Osd, r: u32, comptime fmt: []const u8, args: anytype) void {
    var buf: [osd.COLS]u8 = undefined;
    o.body(r, std.fmt.bufPrint(&buf, fmt, args) catch &buf, false);
}

fn home(s: *const pw.State, o: *osd.Osd) void {
    o.line(0, " ZIGMACHINE  WI-FI         < Esc", true);
    var a: [wc_max]u8 = undefined;
    var b: [wc_max]u8 = undefined;
    const i = &s.info;
    if (!i.known) {
        row(o, 2, "Status  reading...", .{});
    } else if (i.fail == .no_tools) {
        row(o, 2, "Wi-Fi tools not found: {s}", .{if (i.missing) |t| @tagName(t) else "?"});
    } else if (i.fail == .no_iface) {
        row(o, 2, "No Wi-Fi dongle (no wlan0)", .{});
    } else if (i.connected) |c| {
        row(o, 2, "Status  connected", .{});
        row(o, 3, "Network {s}", .{fit(&a, c.slice(), W - 8)});
        row(o, 4, "Address {s}", .{if (i.ip_len != 0) i.ip() else "none (DHCP)"});
    } else {
        row(o, 2, "Status  not connected", .{});
    }
    row(o, 5, "Saved   {s}", .{if (i.saved) |sv| fit(&b, sv.ssid.slice(), W - 8) else "none"});
    for (pw.ITEMS, 0..) |item, k| {
        const t = switch (item) {
            .scan => " Scan networks...",
            .forget => " Forget saved network",
            .back => " Back",
        };
        o.body(ITEM_ROW + @as(u32, @intCast(k)), t, k == s.cursor);
    }
    o.body(RULE, "-" ** W, false);
    var rows: [4][]const u8 = undefined;
    var last: [osd.COLS]u8 = undefined;
    const n = text.wrap(help[s.cursor], W, &rows, &last);
    for (rows[0..n], 0..) |r, k| o.body(HELP + @as(u32, @intCast(k)), r, false);
}

const wc_max = 32;

/// The SSID made showable (page_wifi.shown) and cut to `width` with text.fit's '~'.
fn fit(buf: *[wc_max]u8, ssid: []const u8, width: usize) []const u8 {
    const s = pw.shown(buf, ssid);
    if (s.len <= width) return s;
    buf[width - 1] = text.CUT;
    return buf[0..width];
}

fn list(s: *const pw.State, o: *osd.Osd) void {
    var bar: [osd.COLS]u8 = undefined;
    const title = std.fmt.bufPrint(&bar, " ZIGMACHINE  NETWORKS  {d:>2}/{d:<2} Esc", .{ if (s.n_nets == 0) 0 else s.pick + 1, s.n_nets }) catch "";
    o.line(0, title, true);
    if (s.n_nets == 0) return row(o, 2, "No networks found. R: again", .{});
    const end = @min(s.top + pw.SHOWN, s.n_nets);
    for (s.nets[s.top..end], s.top..) |net, k| {
        var name: [wc_max]u8 = undefined;
        var line: [osd.COLS]u8 = undefined;
        const bars = "####"[0..wp.bars(net.dbm)];
        const t = std.fmt.bufPrint(&line, "{c}{s:<4} {s}", .{ @as(u8, if (net.secured) '*' else ' '), bars, fit(&name, net.ssid.slice(), W - 6) }) catch "";
        o.body(@intCast(1 + k - s.top), t, k == s.pick);
    }
}

fn password(s: *const pw.State, o: *osd.Osd) void {
    o.line(0, " ZIGMACHINE  PASSWORD     Esc", true);
    var name: [wc_max]u8 = undefined;
    row(o, 2, "Join", .{});
    if (s.picked()) |net| row(o, 3, "{s}", .{fit(&name, net.ssid.slice(), W)});
    row(o, 5, "Password ({d})", .{s.pass_len});
    var stars = [_]u8{'*'} ** W;
    const n = @min(s.pass_len, W - 1);
    stars[n] = '_';
    o.body(6, stars[0 .. n + 1], false);
    row(o, 8, "{s}", .{if (s.short) "8 to 63 characters, please" else "Type it; Enter joins."});
    row(o, 10, "Only its hashed key is saved,", .{});
    row(o, 11, "never the password itself.", .{});
}

fn busy(s: *const pw.State, o: *osd.Osd) void {
    o.line(0, " ZIGMACHINE  WI-FI           Esc", true);
    const spin = "|/-\\"[s.phase % 4];
    var name: [wc_max]u8 = undefined;
    switch (s.busy_what) {
        .status => row(o, 3, "{c} Reading the state", .{spin}),
        .scan => row(o, 3, "{c} Scanning", .{spin}),
        .forget => row(o, 3, "{c} Forgetting", .{spin}),
        .join => {
            row(o, 3, "{c} Joining", .{spin});
            if (s.picked()) |net| row(o, 4, "  {s}", .{fit(&name, net.ssid.slice(), W - 2)});
            row(o, 6, "up to 20 s, then DHCP", .{});
        },
    }
    row(o, 9, "Esc leaves; it goes on and", .{});
    row(o, 10, "the result shows below.", .{});
}
