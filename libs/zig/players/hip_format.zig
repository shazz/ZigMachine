// What makes a file a Jochen Hippel Amiga module (.hip) as modland ships it:
// the replay's two-entry jump table (+0 bra INIT, +2 bra PLAY) and, past the
// player code, the song's "TFMX" tag. Pure: no chip, so it is natively tested
// (hip_format_test.zig).

const BRA: u8 = 0x60; // bra.s / bra.w: the jump table's opcode byte
/// How far into the file the song's "TFMX" tag may sit (past the player code).
pub const TAG_SEARCH: usize = 0x4000;

pub fn recognise(file: []const u8) bool {
    if (file.len < 8 or file[0] != BRA or file[2] != BRA) return false;
    const end = @min(file.len, TAG_SEARCH) -| 3;
    var i: usize = 4;
    while (i < end) : (i += 2) {
        if (file[i] == 'T' and file[i + 1] == 'F' and file[i + 2] == 'M' and file[i + 3] == 'X') return true;
    }
    return false;
}
