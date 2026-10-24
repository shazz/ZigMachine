// Who plays the music, for the debug page: the music block at the end of the debug
// mailbox (map_cart.zig "the music: who plays it", cycles/bsndinfo.h), written by the CPU
// that runs the players. Read past the writer: the block is taken only when SI_SEQ is the
// same even value before and after the copy.
const std = @import("std");
const mc = @import("map_cart.zig");
const bus = @import("bus.zig");

pub const State = enum {
    no_cart, // nothing running: the mailbox is the last cart's
    old_fw, // no mailbox, or one older than MB_VERSION_SND_INFO: the firmware cannot say
    off, // no music block: this firmware has no music (ZM_AUDIO=0, or no audio core)
    busy, // the writer was mid-update on every try
    bad_version, // a block version this glass does not know
    ok,
};

pub const Info = struct {
    state: State = .no_cart,
    version: u32 = 0,
    route: u32 = 0,
    player: u32 = 0,
    native: u32 = 0,
    tune: u32 = 0,
    started: bool = false,
    mode: u32 = 0, // SIF_MODE_*: the last zg.requestSndhMode's mode, 0 = none since the load
    cycles: u32 = 0,
    samples: u32 = 0,
    peak_cycles: u32 = 0,
    peak_samples: u32 = 0,
    name_buf: [mc.SND_NAME_MAX + 1]u8 = undefined,
    name_len: usize = 0,

    pub fn name(self: *const Info) []const u8 {
        return self.name_buf[0..self.name_len];
    }
};

const TRIES = 4;

pub fn read(ddr: bus.Ddr) Info {
    const mb = ddr.words[(ddr.bytes() - mc.MB_BYTES) / 4 ..];
    if (mb[0] != mc.MB_MAGIC or mb[1] < mc.MB_VERSION_SND_INFO) return .{ .state = .old_fw };
    const at = (ddr.bytes() - mc.SND_INFO_FROM_TOP) / 4;
    var w: [mc.SND_INFO_WORDS]u32 = undefined;
    for (0..TRIES) |_| {
        const seq = ddr.words[at + mc.SI_SEQ];
        for (&w, 0..) |*x, i| x.* = ddr.words[at + i];
        if (seq & 1 == 0 and ddr.words[at + mc.SI_SEQ] == seq) return decode(&w);
    }
    return .{ .state = .busy };
}

pub fn decode(w: *const [mc.SND_INFO_WORDS]u32) Info {
    if (w[mc.SI_MAGIC] != mc.SND_INFO_MAGIC) return .{ .state = .off };
    const head = w[mc.SI_HEAD];
    var info = Info{ .state = .ok, .version = head & 0xFF };
    if (info.version != mc.SND_INFO_VERSION) {
        info.state = .bad_version;
        return info;
    }
    info.route = head >> 8 & 0xFF;
    info.player = head >> 16 & 0xFF;
    info.native = head >> 24;
    info.tune = w[mc.SI_TUNE];
    info.started = w[mc.SI_FLAGS] & mc.SIF_STARTED != 0;
    info.mode = w[mc.SI_FLAGS] >> mc.SIF_MODE_SHIFT & mc.SIF_MODE_MASK;
    info.cycles = w[mc.SI_CYCLES];
    info.samples = w[mc.SI_SAMPLES];
    info.peak_cycles = w[mc.SI_PEAK_CYCLES];
    info.peak_samples = w[mc.SI_PEAK_SAMPLES];
    var raw: [(mc.SND_INFO_WORDS - mc.SI_NAME) * 4]u8 = undefined;
    for (0..mc.SND_INFO_WORDS - mc.SI_NAME) |i| std.mem.writeInt(u32, raw[i * 4 ..][0..4], w[mc.SI_NAME + i], .little);
    const n = std.mem.indexOfScalar(u8, &raw, 0) orelse mc.SND_NAME_MAX;
    for (raw[0..n], 0..) |c, i| info.name_buf[i] = if (std.ascii.isPrint(c)) c else '?'; // the cart wrote it
    info.name_len = n;
    return info;
}

/// A render's share of real time, in percent: 100 = the CPU did nothing else.
pub fn loadPct(cycles: u32, samples: u32) ?u64 {
    if (samples == 0) return null;
    return @as(u64, cycles) * mc.SND_RATE_HZ * 100 / (@as(u64, samples) * mc.SND_CLOCK_HZ);
}

const COLS = 32; // osd.COLS: a longer line is clipped

/// The page's first row: "music <who> <player> <load now>/<peak>".
pub fn musicLine(buf: *[COLS]u8, i: *const Info) []const u8 {
    var w = std.Io.Writer.fixed(buf);
    w.writeAll("music ") catch {};
    switch (i.state) {
        .no_cart => w.writeAll("- (no cart)") catch {},
        .old_fw => w.writeAll("? firmware too old") catch {},
        .off => w.writeAll("none: no audio in fw") catch {},
        .busy => w.writeAll("? (being written)") catch {},
        .bad_version => w.print("? block v{d}", .{i.version}) catch {},
        .ok => ok(&w, i),
    }
    return w.buffered();
}

/// "<who> <player> <load now>%/<peak>%": the debug page's music row and the F11 overlay's.
pub fn ok(w: *std.Io.Writer, i: *const Info) void {
    okLoad(w, i, true);
}

/// The same row; `peak` false leaves out "/peak%" (the F11 overlay shows the load now only).
pub fn okLoad(w: *std.Io.Writer, i: *const Info, peak: bool) void {
    switch (i.route) {
        mc.ROUTE_BARD_DOWN => return w.writeAll("none: BARD down") catch {},
        mc.ROUTE_ZIGGY => w.writeAll("ZIGGY ") catch {},
        mc.ROUTE_BARD => w.writeAll("BARD ") catch {},
        else => w.print("route#{d} ", .{i.route}) catch {},
    }
    if (i.player == mc.PLAYER_NONE) return w.writeAll("idle") catch {};
    player(w, i);
    if (!i.started) return w.writeAll(" not started") catch {};
    const cur = loadPct(i.cycles, i.samples) orelse return;
    w.print(" {d}%", .{cur}) catch {};
    if (!peak) return;
    if (loadPct(i.peak_cycles, i.peak_samples)) |pk| w.print("/{d}%", .{pk}) catch {};
}

/// The player's name, as the debug page shows it (the control channel's ZMSTAT too).
pub fn player(w: *std.Io.Writer, i: *const Info) void {
    const label: []const u8 = switch (i.player) {
        mc.PLAYER_SNDH => return sndh(w, i),
        mc.PLAYER_SAP => "SAP 6502",
        mc.PLAYER_MOD => "MOD",
        mc.PLAYER_XM => "XM",
        mc.PLAYER_YM => "YM dump",
        mc.PLAYER_PCM => "PCM",
        mc.PLAYER_HIP => "HIP 68k", // ZMSTAT: BARD:HIP_68k
        mc.PLAYER_UNKNOWN => "unknown",
        else => return w.print("player#{d}", .{i.player}) catch {},
    };
    w.writeAll(label) catch {};
}

/// The mode (zg.requestSndhMode): "68k" (1), "nat" (2), "HQ" (3, the samples on PCM).
/// With no switch since the load the native status says it: a load plays a known driver
/// natively, anything else on Musashi (sndh_native.zig recognise).
fn sndh(w: *std.Io.Writer, i: *const Info) void {
    const near = i.native == mc.NATIVE_NEAR_SEQ or i.native == mc.NATIVE_NEAR_TABLES;
    const label: []const u8 = switch (i.mode) {
        1 => if (near) "SNDH 68k~" else "SNDH 68k", // ~: a near miss
        2 => "SNDH nat",
        3 => "SNDH HQ",
        else => switch (i.native) {
            mc.NATIVE_MUSASHI, mc.NATIVE_OFF => "SNDH 68k",
            mc.NATIVE_BEAT_DIS, mc.NATIVE_OFF + 1...mc.NATIVE_LAST => "SNDH nat",
            mc.NATIVE_NEAR_SEQ, mc.NATIVE_NEAR_TABLES => "SNDH 68k~",
            else => return w.print("SNDH n#{d}", .{i.native}) catch {},
        },
    };
    w.writeAll(label) catch {};
}

/// The page's second row: "song  <name>", or "-" while nothing is asked.
pub fn songLine(buf: *[COLS]u8, i: *const Info) []const u8 {
    var w = std.Io.Writer.fixed(buf);
    const has = i.state == .ok and i.player != mc.PLAYER_NONE and i.name_len > 0;
    w.print("song  {s}", .{if (has) i.name() else "-"}) catch {};
    return w.buffered();
}
