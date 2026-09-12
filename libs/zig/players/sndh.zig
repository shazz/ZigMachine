// SNDH header parsing.
//
// An SNDH file is not data, it is a PROGRAM: three branch instructions at
// offsets 0/4/8 (init / exit / play), the magic "SNDH" at 12, then a run of
// tags describing the tune, ending at "HDNS". Everything after that is 68000
// code and its data. So all this module extracts is what the host needs in
// order to CALL the thing: how many subtunes there are, which to start with,
// and how often `play` wants to be called.
//
// Reference: the SNDH v2.1 specification (sndh.atari.org).
const std = @import("std");

pub const MAGIC_OFFSET = 12;
pub const INIT = 0; // offsets of the three entry points, relative to the image
pub const EXIT = 4;
pub const PLAY = 8;

/// Tags are word aligned and the header is small; refuse to scan past this so a
/// file that is not really an SNDH cannot walk us off into its code.
const MAX_HEADER = 4096;

/// Which interrupt the tune wants `play` called from. The player calls `play`
/// itself, so this is really "the one timer NOT to run as an interrupt" — the
/// others (a digidrum timer, typically) still have to tick.
pub const Timer = enum { vbl, a, b, c, d };

pub const Info = struct {
    /// How often `play` must be called, in Hz. 50 (the VBL) when the tune says
    /// nothing — which is what a tune without a timer tag means.
    hz: u16 = 50,
    timer: Timer = .vbl,
    subtunes: u8 = 1,
    /// Which subtune `init` should be given. Tunes count from 1.
    default_tune: u8 = 1,
};

fn is(data: []const u8, at: usize, want: []const u8) bool {
    return at + want.len <= data.len and std.mem.eql(u8, data[at .. at + want.len], want);
}

/// Read ASCII decimal digits at `at`, stopping at the first non-digit.
fn digits(data: []const u8, at: usize, out: *u32) usize {
    var p = at;
    out.* = 0;
    while (p < data.len and data[p] >= '0' and data[p] <= '9') : (p += 1) {
        out.* = out.* * 10 + (data[p] - '0');
    }
    return p;
}

/// Skip a NUL-terminated tag string and the padding byte that word-aligns it.
///
/// The padding is skipped only when it IS padding. Forcing even alignment here
/// (`p + (p & 1)`) silently corrupts the walk on a rip whose next tag begins at
/// an ODD offset: Scout's "##02" starts at 0x45, so the walk landed on the
/// second '#', read "#0", matched nothing, and left subtunes at 1 — which makes
/// a screen's requested subtune fall back to the default without a word.
/// Tag names are ASCII, so a NUL here can only ever be padding.
fn skipString(data: []const u8, at: usize) usize {
    var p = at;
    while (p < data.len and data[p] != 0) p += 1;
    p += 1; // the NUL
    if (p < data.len and data[p] == 0) p += 1; // the padding byte, if there is one
    return p;
}

/// Returns null when `data` is not an SNDH image at all.
pub fn parse(data: []const u8) ?Info {
    if (!is(data, MAGIC_OFFSET, "SNDH")) return null;

    var info: Info = .{};
    var p: usize = MAGIC_OFFSET + 4;
    const end = @min(data.len, MAX_HEADER);

    while (p < end) {
        if (is(data, p, "HDNS")) break;
        p = tag(data, p, &info);
    }
    return info;
}

// One tag, returning where the next one starts. Unknown bytes advance by one:
// the header carries padding, and a tag we do not model must not derail the
// walk — but a wrong guess about a LENGTH would, which is why the tags that
// carry strings are skipped properly rather than searched for.
fn tag(data: []const u8, at: usize, info: *Info) usize {
    var n: u32 = 0;
    // Timer tags: TA/TB/TC/TD are the four MFP timers, !V is the VBL. All of
    // them answer the only question we ask — how often to call `play`.
    for ([_][]const u8{ "TA", "TB", "TC", "TD", "!V" }, [_]Timer{ .a, .b, .c, .d, .vbl }) |t, which| {
        if (is(data, at, t)) {
            const p = digits(data, at + 2, &n);
            if (n > 0 and n <= 1000) {
                info.hz = @intCast(n);
                info.timer = which;
            }
            return skipString(data, p);
        }
    }
    if (is(data, at, "##")) { // subtune count, two ASCII digits, no NUL
        const p = digits(data, at + 2, &n);
        if (n > 0 and n <= 255) info.subtunes = @intCast(n);
        return p;
    }
    if (is(data, at, "!#")) { // default subtune
        const p = digits(data, at + 2, &n);
        if (n > 0 and n <= 255) info.default_tune = @intCast(n);
        return p;
    }
    if (is(data, at, "TIME")) return at + 4 + 2 * @as(usize, info.subtunes); // one word per subtune
    for ([_][]const u8{ "TITL", "COMM", "RIPP", "CONV", "YEAR", "FLAG" }) |t| {
        if (is(data, at, t)) return skipString(data, at + 4);
    }
    return at + 1;
}

test "a tag starting at an ODD offset is still found" {
    // "Scout": YEAR's NUL lands on an even byte, so "##02" begins at an odd one.
    // Aligning past it read "#0" and lost the subtune count.
    const img = "\x60\x00\x00\x10\x60\x00\x00\x20\x60\x00\x00\x30" ++
        "SNDHTITLScout\x00YEAR1988\x00##02\x00TC50\x00HDNS";
    const info = parse(img).?;
    try std.testing.expectEqual(@as(u8, 2), info.subtunes);
    try std.testing.expectEqual(@as(u16, 50), info.hz); // the walk kept its footing
}

test "a file without the magic is not an SNDH" {
    try std.testing.expect(parse("not a tune at all, not one bit") == null);
}

test "a tune with no timer tag replays at the VBL" {
    const img = "\x60\x00\x00\x10\x60\x00\x00\x20\x60\x00\x00\x30SNDHHDNS";
    const info = parse(img).?;
    try std.testing.expectEqual(@as(u16, 50), info.hz);
    try std.testing.expectEqual(@as(u8, 1), info.subtunes);
}

test "the timer tag says WHICH timer drives the replay" {
    const img = "\x60\x00\x00\x10\x60\x00\x00\x20\x60\x00\x00\x30SNDHTA200\x00HDNS";
    try std.testing.expectEqual(Timer.a, parse(img).?.timer);
    const vbl = "\x60\x00\x00\x10\x60\x00\x00\x20\x60\x00\x00\x30SNDHHDNS";
    try std.testing.expectEqual(Timer.vbl, parse(vbl).?.timer);
}

test "the timer tag sets the replay rate and ## the subtune count" {
    const img = "\x60\x00\x00\x10\x60\x00\x00\x20\x60\x00\x00\x30SNDH" ++
        "TITLCrystallized\x00COMM!Cube\x00##04TC200\x00TIME\x00\x01\x00\x02\x00\x03\x00\x04HDNS";
    const info = parse(img).?;
    try std.testing.expectEqual(@as(u16, 200), info.hz);
    try std.testing.expectEqual(Timer.c, info.timer);
    try std.testing.expectEqual(@as(u8, 4), info.subtunes);
}

test "a title mentioning a timer does not become the replay rate" {
    // The walk skips strings properly, so "TC50" inside a title is just text.
    const img = "\x60\x00\x00\x10\x60\x00\x00\x20\x60\x00\x00\x30SNDH" ++
        "TITLTC50 IS NOT A TAG\x00HDNS";
    try std.testing.expectEqual(@as(u16, 50), parse(img).?.hz);
}

test "an implausible timer value is ignored rather than believed" {
    const img = "\x60\x00\x00\x10\x60\x00\x00\x20\x60\x00\x00\x30SNDHTC999999\x00HDNS";
    try std.testing.expectEqual(@as(u16, 50), parse(img).?.hz);
}
