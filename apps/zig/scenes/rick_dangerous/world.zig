// --------------------------------------------------------------------------
// The world's building blocks (the model's a_world.py + pkg_a's RNG, literal):
// the tile map build $398AA, the tile draw $3980E / $3990A, the row copy
// $39854, the checkpoint save $3BA44, the RNG step $39018.
// The screen is 4 interleaved planes, 160 bytes a line; a tile is 8 lines of
// (p0 p1 p2 p3) bytes.
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");

pub const TILEMAP: i64 = 0x39C00; // 44 tile rows x 32; the visible 24 from $39D00
const BLOCKS: i64 = 0x12A70;
pub const PLAYFIELD: i64 = 0x66010;
pub const WORK: i64 = 0x63810;
pub const WORK_DOWN: i64 = 0x6D810;
pub const SCREEN_OFF: i64 = 0x510;

/// Call 12, $39018: exg; rol.l #3,d7; subq.w #7,d7; eor.w d6,d7.
pub fn rng() void {
    const d6 = m.rl(F.RNG_B);
    var d7 = m.rl(F.RNG_A);
    d7 = ((d7 << 3) | (d7 >> 29)) & 0xFFFFFFFF;
    var lo = ((d7 & 0xFFFF) - 7) & 0xFFFF;
    lo ^= d6 & 0xFFFF;
    m.wl(F.RNG_A, d6);
    m.wl(F.RNG_B, (d7 & 0xFFFF0000) | lo);
}

/// $38FF6, the start-up seed ($16051966, $09121967).
pub fn rngSeed() void {
    var d6: i64 = 0x09121967;
    var d7: i64 = 0x16051966;
    d6 = (d6 << 8) & 0xFFFFFFFF;
    d7 = (d7 & 0xFFFF0000) | (d6 & 0xFFFF);
    d7 = (d7 & 0xFFFF0000) | ((d7 - 7) & 0xFFFF);
    d6 = (d6 & 0xFFFF0000) | ((d6 ^ d7) & 0xFFFF);
    m.wl(F.RNG_A, d6);
    m.wl(F.RNG_B, d7);
}

/// $398AA: 11 block rows x 8 blocks from map_ptr, from the block row of
/// map_row; each block is 4 longs, one per tile row (stride $20). a0 starts
/// (map_row & 3) tile rows ABOVE $39C00, so map_row's own row lands there.
pub fn buildTilemap() void {
    const d0 = m.rw(F.MAP_ROW);
    var a0 = TILEMAP - (d0 & 3) * 0x20;
    var a2 = (m.rl(F.MAP_PTR) + (((d0 & 0xFFFC) * 2) & 0xFFFFFFFF)) & 0xFFFFFF;
    for (0..11) |_| {
        var a1 = a0;
        for (0..8) |_| {
            const src = BLOCKS + (m.rb(a2) << 4);
            a2 += 1;
            var k: i64 = 0;
            while (k < 4) : (k += 1) m.copy(a1 + 0x20 * k, src + 4 * k, 4);
            a1 += 4;
        }
        a0 += 0x80;
    }
}

/// $3990A: 8 lines, the 4 plane bytes of one 8-px half of a 16-px group.
fn drawTile(a3: i64, a2_: i64) void {
    var a2 = a2_;
    var y: i64 = 0;
    while (y < 8) : (y += 1) {
        const d = a3 + 0xA0 * y;
        m.wb(d, m.rb(a2));
        m.wb(d + 2, m.rb(a2 + 1));
        m.wb(d + 4, m.rb(a2 + 2));
        m.wb(d + 6, m.rb(a2 + 3));
        a2 += 4;
    }
}

/// $3980E(a0 = tile map row, a1 = screen address, d0 = rows - 1).
pub fn drawTiles(a0_: i64, a1_: i64, d0: i64) void {
    var a0 = a0_;
    var a1 = a1_;
    const bank = m.rl(F.TILE_BANK);
    var r: i64 = 0;
    while (r < (d0 & 0xFFFF) + 1) : (r += 1) {
        var a3 = a1;
        for (0..16) |_| {
            drawTile(a3, (bank + (m.rb(a0) << 5)) & 0xFFFFFF);
            drawTile(a3 + 1, (bank + (m.rb(a0 + 1) << 5)) & 0xFFFFFF);
            a0 += 2;
            a3 += 8;
        }
        a1 += 0x500;
    }
}

/// $39854(a0 = source, a1 = destination, d0 = lines - 1): 128 bytes a line.
pub fn copyRows(a0_: i64, a1_: i64, d0: i64) void {
    var a0 = a0_;
    var a1 = a1_;
    var r: i64 = 0;
    while (r < (d0 & 0xFFFF) + 1) : (r += 1) {
        m.copy(a1, a0, 128);
        a0 += 0xA0;
        a1 += 0xA0;
    }
}

/// $3BA44: Rick x, y, dir, map_row, rick_attr2, rick_ladder -> $3BA3A..
pub fn saveCheckpoint() void {
    m.ww(0x3BA3A, m.rw(0x3A1D4));
    m.ww(0x3BA3C, m.rw(0x3A1D6));
    m.ww(0x3BA3E, m.rw(0x3A1D2));
    m.ww(0x3BA40, m.rw(0x3904C));
    m.wb(0x3BA42, m.rb(0x3CA8D));
    m.wb(0x3BA43, m.rb(0x3B996));
}
