// --------------------------------------------------------------------------
// MP3 PLAYER: the title of an .mp3, from its ID3v2 tag's TIT2 frame (v2.3 /
// v2.4; Latin-1, UTF-8, or UTF-16 with its high bytes dropped), when the tag
// is in the first chunk the player reads anyway. Pure: id3_test.zig.
// --------------------------------------------------------------------------

/// The printable title into `out`, or an empty slice (no tag, no TIT2, past `b`).
pub fn title(b: []const u8, out: []u8) []const u8 {
    if (b.len < 10 or b[0] != 'I' or b[1] != 'D' or b[2] != '3' or (b[3] != 3 and b[3] != 4)) return out[0..0];
    const v4 = b[3] == 4;
    const end = @min(b.len, 10 + syncsafe(b[6..10]));
    var at: usize = 10;
    while (at + 10 <= end) {
        const size: usize = if (v4) syncsafe(b[at + 4 .. at + 8]) else be32(b[at + 4 .. at + 8]);
        if (b[at] == 0 or size == 0) break; // padding
        if (b[at] == 'T' and b[at + 1] == 'I' and b[at + 2] == 'T' and b[at + 3] == '2') {
            const body = at + 10;
            if (body + size > end or size < 2) return out[0..0];
            return text(b[body .. body + size], out);
        }
        at += 10 + size;
    }
    return out[0..0];
}

fn text(f: []const u8, out: []u8) []const u8 {
    const enc = f[0];
    const wide = enc == 1 or enc == 2; // UTF-16 (BOM) / UTF-16BE
    var n: usize = 0;
    var i: usize = 1;
    if (enc == 1 and f.len >= 3) i = 3; // the BOM
    while (i < f.len and n < out.len) {
        const c: u8 = if (wide) wideByte(f, i, enc == 1 and f.len >= 3 and f[1] == 0xFF) else f[i];
        i += if (wide) 2 else 1;
        if (c == 0) break;
        out[n] = if (c >= 0x20 and c < 0x7F) c else '?';
        n += 1;
    }
    return out[0..n];
}

/// A UTF-16 unit's low byte, Latin-1 if the high byte is 0, else '?'.
fn wideByte(f: []const u8, i: usize, le: bool) u8 {
    if (i + 1 >= f.len) return 0;
    const lo = if (le) f[i] else f[i + 1];
    const hi = if (le) f[i + 1] else f[i];
    if (hi == 0 and lo == 0) return 0;
    return if (hi == 0) lo else '?';
}

fn syncsafe(s: []const u8) usize {
    return (@as(usize, s[0] & 0x7F) << 21) | (@as(usize, s[1] & 0x7F) << 14) | (@as(usize, s[2] & 0x7F) << 7) | (s[3] & 0x7F);
}

fn be32(s: []const u8) usize {
    return (@as(usize, s[0]) << 24) | (@as(usize, s[1]) << 16) | (@as(usize, s[2]) << 8) | s[3];
}
