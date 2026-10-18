// --------------------------------------------------------------------------
// XM patterns: the packed cells, read in place (xm_format.zig gives the
// layout). A pattern is a run of rows of `channels` cells; a cell is either
// five bytes (note, instrument, volume column, effect, parameter) or a flag
// byte (bit 7 set) naming which of those five follow, the rest being 0. The
// rows are variable-length, so a row is found only by reading the ones
// before it: scan() reads every row once at load and refuses a pattern that
// runs past its data, and the sequencer then reads row by row.
// Pure: no chip, no allocation. Tested natively (xm_format_test.zig).
// --------------------------------------------------------------------------
const fmt = @import("xm_format.zig");

pub const Cell = struct {
    note: u8 = 0, // 1..96 = C-0..B-7, 97 = key off, 0 = none
    inst: u8 = 0, // 1-based, 0 = none
    vol: u8 = 0, // the volume column: 0x10..0x50 set volume, 0x60..0x9F slides, 0 = none
    eff: u8 = 0,
    param: u8 = 0,
};

/// Where a pattern's packed rows are, in the song image.
pub const PatInfo = struct {
    off: u32 = 0, // first packed row byte
    end: u32 = 0, // one past the packed data
    rows: u16 = 0,
};

fn at(b: []const u8, o: usize) u8 {
    return if (o < b.len) b[o] else 0;
}

/// Read one row of `channels` cells at `start` in `b` into `cells`; returns the
/// offset of the next row. Bytes past `b` read as 0, so a row cut short is
/// caught by the caller's end check, never read out of bounds.
pub fn readRow(b: []const u8, start: usize, channels: usize, cells: *[fmt.MAX_CH]Cell) usize {
    var o = start;
    for (0..channels) |ch| {
        const f = at(b, o);
        if (f & 0x80 != 0) {
            o = readPacked(b, o + 1, f, &cells[ch]);
        } else {
            cells[ch] = .{ .note = f, .inst = at(b, o + 1), .vol = at(b, o + 2), .eff = at(b, o + 3), .param = at(b, o + 4) };
            o += 5;
        }
    }
    return o;
}

/// The fields a packed cell's flag byte names, read from `o` on; returns the offset after them.
fn readPacked(b: []const u8, start: usize, flag: u8, c: *Cell) usize {
    var o = start;
    c.* = .{};
    const fields = [_]struct { bit: u8, dst: *u8 }{
        .{ .bit = 0x01, .dst = &c.note },
        .{ .bit = 0x02, .dst = &c.inst },
        .{ .bit = 0x04, .dst = &c.vol },
        .{ .bit = 0x08, .dst = &c.eff },
        .{ .bit = 0x10, .dst = &c.param },
    };
    for (fields) |f| {
        if (flag & f.bit != 0) {
            f.dst.* = at(b, o);
            o += 1;
        }
    }
    return o;
}

/// Locate every pattern and check its packed rows all fit inside it. Returns
/// the offset one past the last pattern: where the instruments begin.
pub fn scan(data: []const u8, hdr: *const fmt.Header, out: *[fmt.MAX_PATTERNS]PatInfo) fmt.Error!usize {
    var pos: usize = hdr.pattern_data;
    var cells: [fmt.MAX_CH]Cell = undefined;
    for (0..hdr.num_patterns) |p| {
        if (pos + 9 > data.len) return error.Truncated;
        const hl = fmt.rd32(data, pos);
        if (hl < 9 or data[pos + 4] != 0) return error.BadPattern;
        const rows = fmt.rd16(data, pos + 5);
        const packed_size = fmt.rd16(data, pos + 7);
        if (rows == 0 or rows > fmt.MAX_ROWS) return error.BadPattern;
        const off = pos + hl;
        const end = off + packed_size;
        if (end > data.len) return error.Truncated;
        out[p] = .{ .off = @intCast(off), .end = @intCast(end), .rows = rows };
        pos = end;
        if (packed_size == 0) continue; // an empty pattern: FT2 stores no cells at all
        var o = off;
        for (0..rows) |_| {
            o = readRow(data[0..end], o, hdr.channels, &cells);
            if (o > end) return error.Truncated;
        }
    }
    return pos;
}
