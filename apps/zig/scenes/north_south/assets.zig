// --------------------------------------------------------------------------
// What was ripped out of NORTH & SOUTH (Infogrames 1989), by
// tools/private_tools/north_south_assets.py from the disk (ns.app, ba1/ba2.tc0,
// ecr.tc1, carte.ech) and a Hatari RAM dump taken at do_battle ($AAD0).
// Every file is the game's own bytes (see that script's docstring).
// --------------------------------------------------------------------------
const DIR = "../../assets/screens/north_south/";

/// flat $1C3F0..$1DA80 at do_battle: the state the battle starts from.
pub const entry = @embedFile(DIR ++ "entry.bin");
/// flat $17E00..$18C20: ns.app's read-only battle tables.
pub const rom = @embedFile(DIR ++ "rom.bin");
const sprites = @embedFile(DIR ++ "sprites.bin");
/// Per field: 16 ST palette words, then the 32000-byte planar picture.
const fields = @embedFile(DIR ++ "fields.bin");
/// Sequence and sample lengths of carte.ech, for the pacing model's sound player.
pub const sound = @embedFile(DIR ++ "sound.bin");

pub const FIELD_BYTES: usize = 32 + 32000;

pub fn fieldPalette(field: usize, i: usize) u16 {
    return be16(fields, field * FIELD_BYTES + 2 * i) & 0x777;
}
pub fn fieldPicture(field: usize) *const [32000]u8 {
    return fields[field * FIELD_BYTES + 32 ..][0..32000];
}

/// The six sprite banks, in sprites.bin order.
pub const BankId = enum(u3) { union_, confed, decor, fx_a, fx_b, fx_c };
pub const NBANKS = 6;

pub const Sprite = struct {
    w: u16, // pixels (a multiple of 16)
    h: u16,
    /// Bit 7 of the sprite header in RAM at do_battle: the bank is mirrored in
    /// place when a draw asks for the other orientation (pacing only).
    flipped: bool,
    pixels: []const u8, // h rows of w colour indices, 0 = transparent
};

pub const Bank = struct {
    count: u16,
    head: []const u8, // count x 10 bytes
    pix: []const u8,

    pub fn get(self: *const Bank, n: usize) ?Sprite {
        if (n >= self.count) return null;
        const e = self.head[n * 10 ..][0..10];
        const w = be16(e, 0);
        if (w == 0) return null;
        const h = be16(e, 2);
        const off = be32(e, 4);
        return .{ .w = w, .h = h, .flipped = e[8] != 0, .pixels = self.pix[off..][0 .. @as(usize, w) * h] };
    }
};

pub const banks: [NBANKS]Bank = blk: {
    @setEvalBranchQuota(100000);
    var out: [NBANKS]Bank = undefined;
    var p: usize = 0;
    for (0..NBANKS) |i| {
        const n = be16(sprites, p);
        const head = sprites[p + 2 ..][0 .. n * 10];
        var total: usize = 0;
        for (0..n) |k| total += @as(usize, be16(head, k * 10)) * be16(head, k * 10 + 2);
        const pix = sprites[p + 2 + n * 10 ..][0..total];
        out[i] = .{ .count = n, .head = head, .pix = pix };
        p += 2 + n * 10 + total;
        if (p & 1 != 0) p += 1;
    }
    if (p != sprites.len) @compileError("sprites.bin: unexpected length");
    break :blk out;
};

pub fn be16(d: []const u8, o: usize) u16 {
    return @as(u16, d[o]) << 8 | d[o + 1];
}
pub fn be32(d: []const u8, o: usize) u32 {
    return @as(u32, be16(d, o)) << 16 | be16(d, o + 2);
}
