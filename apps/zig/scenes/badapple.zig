// --------------------------------------------------------------------------
// BAD APPLE!! (cart 166): a 1-bit film as a stream of ROW-TRANSITION EDITS, our own player (design: docs/ports/badapple).
//   - SPANS.BIN (format "BASP", tools/badapple/spans.py) is on the .zmd floppy and is read one 1 s (30 frame)
//     ZX0 block at a time, a block ahead (badapple/blocks.zig).
//   - A frame is decoded row by row (badapple/decoder.zig); only the rows whose edges moved are repainted, with
//     CPU memsets, into plane 0's 8-bit buffer.
//   - The clock, palette, failure and the local song are the player the three Bad Apple carts share
//     (badapple/film.zig; 167 is the tile dictionary, 168 the polygon stream).
//   - The disk on the shelf holds OUR synthetic test film (tools/badapple/synth.py). Matt's own build
//     (-Dbadapple_music, prototypes/cards/build_badapple.sh) swaps in the real stream and the song, which are
//     never committed.
// --------------------------------------------------------------------------
const decoder = @import("badapple/decoder.zig");
const film = @import("badapple/film.zig");

const Spans = struct {
    pub const MAGIC = decoder.MAGIC;
    pub const FILE = "SPANS.BIN";
    pub const MAX_PACKED = decoder.MAX_PACKED;
    pub const MAX_RAW = decoder.MAX_RAW;
    pub const State = decoder.State;
};

pub const Demo = film.Film(Spans);
