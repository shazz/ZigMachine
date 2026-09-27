// --------------------------------------------------------------------------
// The game's files, read as its INPUT # / LINE INPUT # / GET # read them:
// DATA.DAT (lines 8-22), SPITFIRE.HSC (2302-2305) and MISSIONS.DAT's
// 301-byte records (1663-1666: FIELD #1, 289 AS md$, 12 AS db$). The
// high-score file is only written in RAM: a browser has no disk to keep it.
// --------------------------------------------------------------------------
const std = @import("std");
const assets = @import("assets.zig");

/// A reader over one text file: fields end at CR, LF or a comma.
pub const Reader = struct {
    s: []const u8,
    p: usize = 0,

    fn skipEnd(r: *Reader) void {
        if (r.p < r.s.len and r.s[r.p] == ',') {
            r.p += 1;
            return;
        }
        while (r.p < r.s.len and (r.s[r.p] == '\r' or r.s[r.p] == '\n')) r.p += 1;
    }

    /// The next field as text (LINE INPUT keeps commas: whole = true).
    pub fn field(r: *Reader, whole: bool) []const u8 {
        const a = r.p;
        while (r.p < r.s.len) : (r.p += 1) {
            const c = r.s[r.p];
            if (c == '\r' or c == '\n' or (!whole and c == ',')) break;
        }
        const out = r.s[a..r.p];
        r.skipEnd();
        return out;
    }

    pub fn int(r: *Reader) i32 {
        const f = std.mem.trim(u8, r.field(false), " ");
        return std.fmt.parseInt(i32, f, 10) catch 0;
    }
};

pub fn data() Reader {
    return .{ .s = assets.DATA_DAT };
}

pub const REC: usize = 301;

pub const Mission = struct {
    text: []const u8,
    tgtx: i32,
    strtx: i32,
    mission: i32,
    misf: i32,
    mfin: i32,
    bonus: i32,
    msb: i32,
    meb: i32,
};

/// GET #1, n (1-based); null past the file's end.
pub fn mission(n: i32) ?Mission {
    if (n < 1) return null;
    const at = @as(usize, @intCast(n - 1)) * REC;
    if (at + REC > assets.MISSIONS_DAT.len) return null;
    const r = assets.MISSIONS_DAT[at..][0..REC];
    const d = r[289..];
    return .{
        .text = r[0..289],
        .tgtx = @as(i32, d[0]) * 256 + d[1],
        .strtx = @as(i32, d[2]) * 256 + d[3],
        .mission = d[4],
        .misf = d[5],
        .mfin = d[6],
        .bonus = @as(i32, d[7]) * 256 + d[8],
        .msb = d[9],
        .meb = d[10],
    };
}
