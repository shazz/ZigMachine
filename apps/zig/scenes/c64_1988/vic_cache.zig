// --------------------------------------------------------------------------
// Sprite blocks expanded to chunky pixels, once: what vic_paint.zig copies (CHISEL, or a keyed
// CPU copy) instead of decoding every row's bits on every line.
//
// A block is 63 bytes, 21 rows of 3; expanded, a row is 24 pixels (48 X-expanded), 0 where the
// sprite is transparent. The pixels are not colours but a colour GROUP's entries (groups.zig):
// palette index FIRST + 4 * group + code, code 1 $D025, 2 the sprite's own colour, 3 $D026
// (hires pixels are code 2). The group's three entries hold the colours, so a fade step is
// three palette writes, not every block of the logo expanded again. A block keeps the last
// (hires or multicolour, X-expanded or not, group) it was asked for, and is expanded again
// only when asked another (in this intro: a glyph moving to another group, almost never).
// Blocks: VIC bank 3's 256 ($C000-$FFFF) and bank 0's 32 at $2000-$27FF, the only bank 0
// memory with sprite data (vic_draw.Mem).
// --------------------------------------------------------------------------
const px = @import("vic_pixels.zig");

pub const ROWS = 21;
pub const MAX_W = 48;
pub const SLOTS = 256 + 32;
pub const IMAGE = ROWS * MAX_W;
pub const FIRST: u8 = 32; // the groups' palette entries: FIRST + 4 * group + code
pub const GROUPS = 16;

/// How a block is drawn: its mode and its colour group.
pub const Look = struct {
    mcol: bool,
    xe2: bool,
    group: u8,

    pub fn eql(a: Look, b: Look) bool {
        return a.mcol == b.mcol and a.xe2 == b.xe2 and a.group == b.group;
    }

    pub fn width(self: Look) u16 {
        return if (self.xe2) 48 else 24;
    }
};

/// The slot of block `block` in bank 3 (`bank3`) or bank 0; null for bank 0 memory that is
/// not sprite data (it reads as 0: nothing to show).
pub fn slot(bank3: bool, block: u16) ?u16 {
    if (bank3) return block & 0xFF;
    if (block >= 0x80 and block < 0xA0) return 256 + (block - 0x80);
    return null;
}

pub const Cache = struct {
    images: *[SLOTS][IMAGE]u8,
    looks: [SLOTS]?Look = .{null} ** SLOTS,
    expansions: u32 = 0, // how many blocks were (re-)expanded: a test bounds it

    /// The expanded block in slot `s` drawn as `look`, rows `width` apart. `bytes` are its 63.
    pub fn image(self: *Cache, s: u16, look: Look, bytes: *const [63]u8) []const u8 {
        const img = &self.images[s];
        if (self.looks[s] == null or !self.looks[s].?.eql(look)) {
            expand(img, look, bytes);
            self.looks[s] = look;
            self.expansions += 1;
        }
        return img[0 .. ROWS * @as(usize, look.width())];
    }
};

/// Expand 21 rows of 3 bytes into `img` (rows look.width() apart).
pub fn expand(img: *[IMAGE]u8, look: Look, bytes: *const [63]u8) void {
    const w: usize = look.width();
    const xe: usize = if (look.xe2) 2 else 1;
    const base = FIRST + 4 * look.group;
    for (0..ROWS) |r| {
        const row = img[r * w ..][0..w];
        for (0..3) |j| {
            const codes = px.codes(look.mcol, bytes[3 * r + j]);
            for (codes, 0..) |v, p| {
                const ink = if (v == 0) 0 else base + v;
                for (0..xe) |e| row[(8 * j + p) * xe + e] = ink;
            }
        }
    }
}
