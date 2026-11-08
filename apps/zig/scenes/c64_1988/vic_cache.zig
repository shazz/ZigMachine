// --------------------------------------------------------------------------
// Sprite blocks expanded to chunky pixels, once: what vic_draw.zig copies (CHISEL, or a keyed
// CPU copy) instead of decoding every row's bits on every line.
//
// A block is 63 bytes, 21 rows of 3; expanded, a row is 24 palette indices (48 X-expanded),
// 0 where the sprite is transparent. The expansion depends on the block's bytes (static: the
// ripped banks) and on how it is shown: hires or multicolour, X-expanded or not, and its three
// colours ($D025, the sprite's $D027+n, $D026). Each block keeps the last one it was asked for;
// a different one (a fade step, a part switch) expands it again. In this intro a block is only
// ever shown one way at a time, so that is once per colour change, not once per frame.
// Blocks: VIC bank 3's 256 ($C000-$FFFF) and bank 0's 32 at $2000-$27FF, the only bank 0
// memory with sprite data (vic_draw.Mem).
// --------------------------------------------------------------------------
const px = @import("vic_pixels.zig");

pub const ROWS = 21;
pub const MAX_W = 48;
pub const SLOTS = 256 + 32;
pub const IMAGE = ROWS * MAX_W;

/// How a block is shown. `colours` are the plane indices for codes 1..3 (index 0 unused).
pub const Look = struct {
    mcol: bool,
    xe2: bool,
    colours: [4]u8,

    pub fn eql(a: Look, b: Look) bool {
        return a.mcol == b.mcol and a.xe2 == b.xe2 and a.colours[1] == b.colours[1] and
            a.colours[2] == b.colours[2] and a.colours[3] == b.colours[3];
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

    /// The expanded block in slot `s` shown as `look`, rows `width` apart. `bytes` are its 63.
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
    for (0..ROWS) |r| {
        const row = img[r * w ..][0..w];
        for (0..3) |j| {
            const codes = px.codes(look.mcol, bytes[3 * r + j]);
            for (codes, 0..) |v, p| {
                const ink = look.colours[v]; // colours[0] is 0: transparent
                for (0..xe) |e| row[(8 * j + p) * xe + e] = ink;
            }
        }
    }
}
