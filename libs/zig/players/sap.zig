// --------------------------------------------------------------------------
// The SAP file (Slight Atari Player): a text header of tags, then the tune's
// 6502 code and data as Atari binary blocks. From the format's specification
// text (Adam Bienias, "SAP file format"); no ASAP source was read.
//
//   "SAP" CR LF, then one tag a line (CR LF):
//     AUTHOR "..."  NAME "..."  DATE "..."   text, quoted
//     SONGS n  DEFSONG n (0-based)          subsongs, the one to start
//     STEREO  NTSC                          flags: a second POKEY; the NTSC clock
//     TYPE B|C|D|S|R                        how the player is called
//     FASTPLAY n                            scanlines between calls (default 312 PAL, 262 NTSC)
//     INIT hhhh  MUSIC hhhh  PLAYER hhhh    addresses, hex
//     TIME mm:ss.xxx [LOOP]                 a song's length (one a song; read, not used)
//   then the blocks: $FF $FF, then start and end (little-endian, inclusive) and
//   the bytes; the $FFFF is optional before every block after the first.
//
// Played here: TYPE B (INIT with A = song, then PLAYER every FASTPLAY lines)
// and TYPE C (CMC: PLAYER+3 with A=$70 X/Y=MUSIC, PLAYER+3 with A=0 X=song,
// then PLAYER+6 every FASTPLAY lines). Everything else is refused with a reason.
// --------------------------------------------------------------------------
const std = @import("std");

pub const Type = enum(u8) { b = 'B', c = 'C' };

pub const Refusal = enum(u8) {
    none = 0,
    not_sap, // no "SAP" magic
    no_data, // no $FFFF binary after the header
    bad_tag, // a tag's value does not parse
    unsupported_type, // TYPE D, S, R (or none)
    stereo, // a second POKEY: not yet
    missing_address, // TYPE B without INIT or PLAYER, TYPE C without MUSIC or PLAYER
    bad_block, // a block ends before it starts, or runs past the file
};

pub const Info = struct {
    type: Type = .b,
    init: u16 = 0,
    music: u16 = 0,
    player: u16 = 0,
    songs: u8 = 1,
    defsong: u8 = 0,
    ntsc: bool = false,
    fastplay: u16 = 0, // scanlines a call; 0 until parsed: 312 PAL, 262 NTSC
    data: usize = 0, // where the binary starts in the file
    have: u8 = 0, // bit 0 INIT, 1 MUSIC, 2 PLAYER, 3 TYPE, 4 STEREO
};

pub const Parsed = union(enum) { ok: Info, refused: Refusal };

fn hex16(v: []const u8) ?u16 {
    return std.fmt.parseInt(u16, std.mem.trim(u8, v, " "), 16) catch null;
}

fn dec(v: []const u8, comptime T: type) ?T {
    return std.fmt.parseInt(T, std.mem.trim(u8, v, " "), 10) catch null;
}

/// One header line into `info`: false if its value does not parse.
fn tag(info: *Info, line: []const u8) bool {
    const sp = std.mem.indexOfScalar(u8, line, ' ') orelse line.len;
    const key = line[0..sp];
    const v = if (sp < line.len) line[sp + 1 ..] else "";
    if (std.mem.eql(u8, key, "TYPE")) {
        info.have |= 8;
        const c: u8 = if (v.len > 0) v[0] else 0;
        if (c == 'B' or c == 'C') {
            info.type = @enumFromInt(c);
        } else info.have &= ~@as(u8, 8); // known tag, unsupported value: refused once the header is read
    } else if (std.mem.eql(u8, key, "STEREO")) {
        info.have |= 16;
    } else if (std.mem.eql(u8, key, "NTSC")) {
        info.ntsc = true;
    } else if (std.mem.eql(u8, key, "SONGS")) {
        info.songs = dec(v, u8) orelse return false;
    } else if (std.mem.eql(u8, key, "DEFSONG")) {
        info.defsong = dec(v, u8) orelse return false;
    } else if (std.mem.eql(u8, key, "FASTPLAY")) {
        info.fastplay = dec(v, u16) orelse return false;
    } else inline for (.{ .{ "INIT", "init", 1 }, .{ "MUSIC", "music", 2 }, .{ "PLAYER", "player", 4 } }) |t| {
        if (std.mem.eql(u8, key, t[0])) {
            @field(info, t[1]) = hex16(v) orelse return false;
            info.have |= t[2];
        }
    }
    return true; // AUTHOR, NAME, DATE, TIME, COVOX and unknown tags: not needed to play
}

pub fn parse(file: []const u8) Parsed {
    if (!std.mem.startsWith(u8, file, "SAP\r\n") and !std.mem.startsWith(u8, file, "SAP\n")) return .{ .refused = .not_sap };
    const data = std.mem.indexOf(u8, file, "\xFF\xFF") orelse return .{ .refused = .no_data };
    var info = Info{ .data = data };
    var lines = std.mem.tokenizeAny(u8, file[0..data], "\r\n");
    _ = lines.next(); // "SAP"
    while (lines.next()) |line| if (!tag(&info, line)) return .{ .refused = .bad_tag };
    if (info.have & 8 == 0) return .{ .refused = .unsupported_type };
    if (info.have & 16 != 0) return .{ .refused = .stereo };
    const need: u8 = if (info.type == .b) 1 | 4 else 2 | 4;
    if (info.have & need != need) return .{ .refused = .missing_address };
    if (info.fastplay == 0) info.fastplay = if (info.ntsc) 262 else 312;
    if (info.defsong >= info.songs) info.defsong = 0;
    if (blocks(file[data..], null) == null) return .{ .refused = .bad_block };
    return .{ .ok = info };
}

/// Walk the binary blocks; copy them into `ram` if given. The bytes loaded, or
/// null if a block is malformed.
pub fn blocks(bin: []const u8, ram: ?*[65536]u8) ?usize {
    var i: usize = 0;
    var total: usize = 0;
    while (i < bin.len) {
        if (i + 2 <= bin.len and bin[i] == 0xFF and bin[i + 1] == 0xFF) i += 2;
        if (i + 4 > bin.len) return null;
        const start = std.mem.readInt(u16, bin[i..][0..2], .little);
        const end = std.mem.readInt(u16, bin[i + 2 ..][0..2], .little);
        i += 4;
        if (end < start) return null;
        const n = @as(usize, end - start) + 1;
        if (i + n > bin.len) return null;
        if (ram) |r| @memcpy(r[start..][0..n], bin[i..][0..n]);
        i += n;
        total += n;
    }
    return total;
}
