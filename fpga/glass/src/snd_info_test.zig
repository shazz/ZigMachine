// The debug page's music rows (snd_info.zig) over a fake mailbox page, laid out as
// cycles/bsndinfo.h writes it: what the page says for each route, player and state.
const std = @import("std");
const mc = @import("map_cart.zig");
const bus = @import("bus.zig");
const osd = @import("osd.zig");
const snd_info = @import("snd_info.zig");
const page_debug = @import("page_debug.zig");

const PAGE = mc.MB_BYTES / 4;
const AT = (mc.MB_BYTES - mc.SND_INFO_FROM_TOP) / 4;

const Song = struct {
    route: u32 = mc.ROUTE_BARD,
    player: u32 = mc.PLAYER_SNDH,
    native: u32 = mc.NATIVE_MUSASHI,
    started: bool = true,
    mode: u32 = 0, // SIF_MODE_*: 0 = no zg.requestSndhMode since the load
    cycles: u32 = 0,
    samples: u32 = 0,
    peak_cycles: u32 = 0,
    peak_samples: u32 = 0,
    name: []const u8 = "",
};

/// A page as a version-2 firmware leaves it, with the music block `s` (null: none).
fn page(words: *[PAGE]u32, s: ?Song) bus.Ddr {
    @memset(words, 0);
    words[0] = mc.MB_MAGIC;
    words[1] = mc.MB_VERSION_SND_INFO;
    const song = s orelse return .{ .words = words };
    const b = words[AT..];
    b[mc.SI_MAGIC] = mc.SND_INFO_MAGIC;
    b[mc.SI_SEQ] = 6;
    b[mc.SI_HEAD] = mc.SND_INFO_VERSION | song.route << 8 | song.player << 16 | song.native << 24;
    b[mc.SI_FLAGS] = (if (song.started) mc.SIF_STARTED else 0) | song.mode << mc.SIF_MODE_SHIFT;
    b[mc.SI_CYCLES] = song.cycles;
    b[mc.SI_SAMPLES] = song.samples;
    b[mc.SI_PEAK_CYCLES] = song.peak_cycles;
    b[mc.SI_PEAK_SAMPLES] = song.peak_samples;
    var name = [_]u8{0} ** ((mc.SND_INFO_WORDS - mc.SI_NAME) * 4);
    @memcpy(name[0..song.name.len], song.name);
    for (0..mc.SND_INFO_WORDS - mc.SI_NAME) |i| b[mc.SI_NAME + i] = std.mem.readInt(u32, name[i * 4 ..][0..4], .little);
    return .{ .words = words };
}

/// The debug page drawn over `ddr`: each `want` must be on it.
fn expectPage(ddr: bus.Ddr, wants: []const []const u8) !void {
    var o = osd.Osd{};
    const v = page_debug.View{ .snd = snd_info.read(ddr) };
    page_debug.draw(&o, &v);
    var dump: [osd.ROWS * (osd.COLS + 1)]u8 = undefined;
    o.dump(&dump);
    for (wants) |want| if (std.mem.indexOf(u8, &dump, want) == null) {
        std.debug.print("missing \"{s}\" in:\n{s}", .{ want, dump });
        return error.TestExpectedEqual;
    };
}

test "BARD playing an SNDH on Musashi: the player, the song and its load now/peak" {
    var w: [PAGE]u32 = undefined;
    // 3.3 Mc for a 60 Hz frame's 735 samples = 198 % of BARD; the peak 3.8 Mc = 228 %
    const ddr = page(&w, .{ .cycles = 3_300_000, .samples = 735, .peak_cycles = 3_800_000, .peak_samples = 735, .name = "auf_weidersehen_monty_digi.sndh" });
    try expectPage(ddr, &.{ "music BARD SNDH 68k 198%/228%", "song  auf_weidersehen_monty_di" });
}

test "ZIGGY playing a MOD, and a native SNDH driver on BARD" {
    var w: [PAGE]u32 = undefined;
    try expectPage(page(&w, .{ .route = mc.ROUTE_ZIGGY, .player = mc.PLAYER_MOD, .cycles = 500_000, .samples = 2205, .name = "lollapalooza.mod" }), &.{ "music ZIGGY MOD 10%", "song  lollapalooza.mod" });
    try expectPage(page(&w, .{ .native = mc.NATIVE_BEAT_DIS, .cycles = 720_000, .samples = 735, .peak_cycles = 720_000, .peak_samples = 735, .name = "union/beat_dis.sndh" }), &.{"music BARD SNDH nat 43%/43%"});
    try expectPage(page(&w, .{ .player = mc.PLAYER_SAP, .name = "Warhawk.sap" }), &.{"music BARD SAP 6502"});
}

test "no music: a firmware without audio, BARD that never answered, nothing asked, a song that never started" {
    var w: [PAGE]u32 = undefined;
    try expectPage(page(&w, null), &.{ "music none: no audio in fw", "song  -" });
    try expectPage(page(&w, .{ .route = mc.ROUTE_BARD_DOWN, .player = mc.PLAYER_NONE }), &.{ "music none: BARD down", "song  -" });
    try expectPage(page(&w, .{ .player = mc.PLAYER_NONE }), &.{"music BARD idle"});
    try expectPage(page(&w, .{ .started = false, .name = "gone.sndh" }), &.{ "music BARD SNDH 68k not started", "song  gone.sndh" });
    var o = osd.Osd{};
    page_debug.draw(&o, &page_debug.View{}); // no cart running: the glass does not read the page
    var dump: [osd.ROWS * (osd.COLS + 1)]u8 = undefined;
    o.dump(&dump);
    try std.testing.expect(std.mem.indexOf(u8, &dump, "music - (no cart)") != null);
}

test "codes this glass does not know are named by number, never guessed" {
    var w: [PAGE]u32 = undefined;
    try expectPage(page(&w, .{ .player = 9, .name = "tune.xyz" }), &.{"music BARD player#9"});
    try expectPage(page(&w, .{ .player = mc.PLAYER_UNKNOWN, .name = "tune.xyz" }), &.{"music BARD unknown"});
    try expectPage(page(&w, .{ .native = mc.NATIVE_LAST + 1 }), &.{"music BARD SNDH n#17"});
    try expectPage(page(&w, .{ .route = 5 }), &.{"music route#5 SNDH 68k"});
    _ = page(&w, .{});
    w[AT + mc.SI_HEAD] = 2; // a block version from a newer firmware
    try expectPage(.{ .words = &w }, &.{"music ? block v2"});
}

test "an old mailbox, a block mid-update, and a name with bytes the OSD cannot show" {
    var w: [PAGE]u32 = undefined;
    _ = page(&w, .{ .name = "x.sndh" });
    w[1] = 1; // mailbox version 1: the page's tail may be the last cart's
    try expectPage(.{ .words = &w }, &.{"music ? firmware too old"});
    w[1] = mc.MB_VERSION_SND_INFO;
    w[AT + mc.SI_SEQ] = 7; // the writer is between its two bumps
    try expectPage(.{ .words = &w }, &.{"music ? (being written)"});
    _ = page(&w, .{ .name = "a\x01b.mod", .player = mc.PLAYER_MOD });
    try expectPage(.{ .words = &w }, &.{"song  a?b.mod"});
}

test "the load is the render's share of real time" {
    try std.testing.expectEqual(@as(?u64, 100), snd_info.loadPct(1_666_667, 735)); // a whole 60 Hz frame of the sys clock
    try std.testing.expectEqual(@as(?u64, 50), snd_info.loadPct(1_666_667, 1470));
    try std.testing.expectEqual(@as(?u64, null), snd_info.loadPct(5, 0));
}

test "the SNDH mode: a switch the firmware published, else what the load left" {
    var w: [PAGE]u32 = undefined;
    const beat = Song{ .native = mc.NATIVE_BEAT_DIS, .cycles = 400_000, .samples = 735 }; // 24 %
    try expectPage(page(&w, beat), &.{"music BARD SNDH nat 24%"});
    var hq = beat;
    hq.mode = 3; // zg.requestSndhMode(3): the samples on a PCM channel
    try expectPage(page(&w, hq), &.{"music BARD SNDH HQ 24%"});
    hq.mode = 1; // back on Musashi, the driver still known
    try expectPage(page(&w, hq), &.{"music BARD SNDH 68k 24%"});
    try expectPage(page(&w, .{ .native = 5 }), &.{"music BARD SNDH nat"}); // Monty: native at load
    try expectPage(page(&w, .{ .native = mc.NATIVE_NEAR_SEQ, .mode = 1 }), &.{"music BARD SNDH 68k~"});
    try expectPage(page(&w, .{ .native = mc.NATIVE_LAST + 1, .mode = 2 }), &.{"music BARD SNDH nat"});
}
