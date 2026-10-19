// The control channel's `stats` line (docs/FPGA_GLASS.md, "The control channel"): what
// the F11 overlay and the debug page's music rows say, as one line a script parses:
//
//   ZMSTAT cart=<file> fps=<x.y> frame_ms=<x.y> bard=<now>/<peak> player=<who>:<player>
//          state=<state> frames=<n> secs=<x.y> missed=<n> beat=<n> trap=<code> err=<name>
//          vs_n=<n> frame_c=<c> ... cal_fill2=<span>/<comp> song=<name>
//
// Every field is `key=value`, values never hold a space ('_' stands in), `-` is "none" or
// "not measured". fps, frame_ms, frames and missed are over the window asked for
// (beats.zig): frame_ms is the mean WALL time of a frame (the firmware does not publish
// the cart's own CPU time), missed the 60 Hz VBLs that showed no new frame. bard is the
// sound CPU's load in percent of real time (now/peak since the song started), `-` when
// BARD does not play the music. Then the video probe's fields (vstat.zig: vs_n= ... cal_fill2=,
// `-` from a firmware without it). song is last, so a parser may take the rest of the line.
const std = @import("std");
const map = @import("map.zig");
const mc = @import("map_cart.zig");
const beats = @import("beats.zig");
const snd_info = @import("snd_info.zig");
const stats = @import("stats.zig");
const vstat = @import("vstat.zig");

pub const State = enum {
    idle, // nothing loaded yet
    booting, // let out of reset, not RUNNING yet
    running,
    stalled, // RUNNING, but no frame finished for STALL_MS: a hang
    request, // asking the glass for a cart swap
    trapped, // the cart trapped (at boot or later)
    silent, // the load's boot never reported RUNNING (loader CartSilent)
    failed, // the load failed otherwise (err= says why)
    quit, // stopped by `quit-cart`
};

pub const STALL_MS = 2000;

/// What the line says the cart is doing. `running`: the app has a cart (App.current).
pub fn state(running: bool, cart_state: u32, still_ms: i64, s: *const stats.Stats) State {
    if (!running) return switch (s.stop) {
        .idle => .idle,
        .quit => .quit,
        .trapped => .trapped,
        .failed => if (isSilent(s.last_err)) .silent else .failed,
    };
    return switch (cart_state & map.CART_STATE_MASK) {
        map.CART_RUNNING => if (still_ms >= STALL_MS) .stalled else .running,
        map.CART_TRAPPED => .trapped,
        mc.CART_REQUEST => .request,
        else => .booting,
    };
}

fn isSilent(err: ?anyerror) bool {
    const e = err orelse return false;
    return e == error.CartSilent;
}

pub const Line = struct {
    cart: []const u8 = "-",
    state: State = .idle,
    secs: u32 = 5,
    rate: ?beats.Rate = null,
    snd: snd_info.Info = .{},
    beat: u32 = 0,
    trap: ?u32 = null,
    err: ?anyerror = null,
    vs: vstat.Info = .{},
};

pub fn write(w: *std.Io.Writer, l: *const Line) std.Io.Writer.Error!void {
    try w.writeAll("ZMSTAT cart=");
    try token(w, l.cart);
    const r = l.rate;
    try w.writeAll(" fps=");
    try tenths(w, if (r) |x| x.fpsX10() else null);
    try w.writeAll(" frame_ms=");
    try tenths(w, if (r) |x| x.frameMsX10() else null);
    try w.writeAll(" bard=");
    try bard(w, &l.snd);
    try w.writeAll(" player=");
    try player(w, &l.snd);
    try w.print(" state={t} frames=", .{l.state});
    try opt(w, if (r) |x| x.frames else null);
    try w.writeAll(" secs=");
    try tenths(w, if (r) |x| @intCast(@divTrunc(x.ms, 100)) else null);
    try w.writeAll(" missed=");
    try opt(w, if (r) |x| x.missed else null);
    try w.print(" beat={d} trap=", .{l.beat});
    try opt(w, l.trap);
    try w.writeAll(" err=");
    try token(w, if (l.err) |e| @errorName(e) else "-");
    try vstat.write(w, &l.vs);
    try w.writeAll(" song=");
    const has = l.snd.state == .ok and l.snd.player != mc.PLAYER_NONE and l.snd.name_len > 0;
    try token(w, if (has) l.snd.name() else "-");
    try w.writeAll("\n");
}

/// A value with no space in it, never empty.
fn token(w: *std.Io.Writer, s: []const u8) !void {
    if (s.len == 0) return w.writeAll("-");
    for (s) |c| try w.writeByte(if (c == ' ' or c == '\t') '_' else if (std.ascii.isPrint(c)) c else '?');
}

fn tenths(w: *std.Io.Writer, v: ?u32) !void {
    const x = v orelse return w.writeAll("-");
    try w.print("{d}.{d}", .{ x / 10, x % 10 });
}

fn opt(w: *std.Io.Writer, v: ?u32) !void {
    const x = v orelse return w.writeAll("-");
    try w.print("{d}", .{x});
}

fn bard(w: *std.Io.Writer, i: *const snd_info.Info) !void {
    const playing = i.state == .ok and i.route == mc.ROUTE_BARD and i.player != mc.PLAYER_NONE and i.started;
    const now = if (playing) snd_info.loadPct(i.cycles, i.samples) else null;
    const cur = now orelse return w.writeAll("-");
    try w.print("{d}/", .{cur});
    const peak = snd_info.loadPct(i.peak_cycles, i.peak_samples) orelse return w.writeAll("-");
    try w.print("{d}", .{peak});
}

/// <who>:<player>, `-` with no cart, or why the firmware cannot say.
fn player(w: *std.Io.Writer, i: *const snd_info.Info) !void {
    switch (i.state) {
        .no_cart => return w.writeAll("-"),
        .old_fw => return w.writeAll("old_fw"),
        .off => return w.writeAll("none"),
        .busy => return w.writeAll("busy"),
        .bad_version => return w.print("block_v{d}", .{i.version}),
        .ok => {},
    }
    const who: []const u8 = switch (i.route) {
        mc.ROUTE_BARD_DOWN => return w.writeAll("BARD_down"),
        mc.ROUTE_ZIGGY => "ZIGGY",
        mc.ROUTE_BARD => "BARD",
        else => "route?",
    };
    try w.print("{s}:", .{who});
    if (i.player == mc.PLAYER_NONE) return w.writeAll("idle");
    var buf: [32]u8 = undefined;
    var name = std.Io.Writer.fixed(&buf);
    snd_info.player(&name, i);
    try token(w, name.buffered());
    if (!i.started) try w.writeAll("_not_started");
}
