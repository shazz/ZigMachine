// --------------------------------------------------------------------------
// BAD APPLE!! TILES (cart 167): the same film as cart 166 as a TILE DICTIONARY, our own design (R91,
// docs/ports/badapple/README.md). 40 x 25 slots of 8x8 1-bit tiles; each 1 s ZX0 block of TILES.BIN carries
// its own dictionary (all-black / all-white implicit) and a key frame, then each frame names only the slots that
// changed (a row mask, slot masks, one code a slot). The player (clock, read-ahead, palette, song) is cart 166's
// (badapple/film.zig), so the three Bad Apple carts compare like for like on the board.
// --------------------------------------------------------------------------
const tiles = @import("badapple/tiles.zig");
const film = @import("badapple/film.zig");

const Tiles = struct {
    pub const MAGIC = tiles.MAGIC;
    pub const FILE = "TILES.BIN";
    pub const MAX_PACKED = tiles.MAX_PACKED;
    pub const MAX_RAW = tiles.MAX_RAW;
    pub const State = tiles.State;
};

pub const Demo = film.Film(Tiles);
