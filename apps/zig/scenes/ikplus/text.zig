// --------------------------------------------------------------------------
// The scrolltext, and its compile-time layout into the four sizes.
//
// game.go's getFullText() word for word, control codes included.  A "^CsN;"
// switches the size the FOLLOWING text is drawn at; the four tiles arrays each
// carry only the characters active at their size (everything else is a space),
// so at any moment exactly one of them has ink where the screen is.
//
// The switch is made by the glyph at the LEADING (right-hand) edge, before that
// glyph is on screen -- updateActSizeFromScroll -- so a section is already the
// right size when it scrolls in.  fontChanges are the glyph positions of the
// codes; position counts NON-control characters, the same indexing the tiles
// arrays use.
//
// All of this is comptime: the strings never reach the machine.
// --------------------------------------------------------------------------
const std = @import("std");

pub const SOURCE =
        "          THE UNION IS PROUD TO PRESENT YOU :                 ^Cs2;INTERNATIONAL KARATE PLUS     ^Cs0;CR" ++
        "ACKED  BY                 ^Cs3;DOM AND CORWIN   ^Cs1;FROM THE         ^Cs3;REPLICANTS AND DMA   ^Cs1; PR" ++
        "ESS F1-F5 AND SEE (IF YOU CAN !!!!) AND LIST..........    A SPECIAL HI TO WILD-XEROX OR RANK-COPPER MY M" ++
        "ASTER!!!!!ARF.... HEEEUUUU JUST A LITTLE QUESTION : WHO HAVE         ^Cs2;BARBARIAN 2 ????????     ^Cs1;" ++
        "RRRRHHHHHAAAAAAAAAAA!!!!!! ANYBODY ????? I NEED BLOOD RRRHHAAAA!!!!! NEED HEAD !!!!! OOOUUUIIIINNNN I WE" ++
        "EP .. I CRY...... I RAVE , I'M DELIRIOUS I'M CAUGHT IN THE ACT-HANDED!!!!!!!         ^Cs0;OK KO I STOP, " ++
        "I RESET, I BREAK, I DRINK,I FLY, I CR...-CR... HIHIHI FINALLY I SAY :                 ^Cs3;SHEAT       " ++
        "^Cs2;HEY HAVE-YOU CANAL PLUS??????????    WHAT ???????    I SAY CANAL PLUS    BORDEL !! (IN FRENCH) YOU " ++
        "DON'T HAVE !!!! BUY THIS AND YOU WILL SEE MY MASTER : I NAME : RANK-COOPER ARF ARF HE TURN ONE'S BACK ON" ++
        " THE CAMERA    OOOUUFF!!!HIHI GGGGGGGGGOOOOOOOOODDDDDDDDD     ^Cs1;IT'S ALL FOR DAY......         ^Cs0;R" ++
        "EMEMBER YOU BARBARIAN 2 AND CANAL PLUS AND MY MASTER OF COURSE........ HI TO : ALL MEMBERS OF DMA(ESPECI" ++
        "ALLY LOCKBUSTER FOR ORIGINAL), DELTA FORCE, TEX, BLADE RUNNERS, CHON-CHON, ALDO, ST-CONNEXION, THE HOBBI" ++
        "T BROTHERS, ABC 85, THE BARBARIANS.......                 ^Cs0;              ";

/// A "^CsN;" is five bytes; N is the size the text after it is drawn at.
fn controlAt(text: []const u8, i: usize) ?u2 {
    if (i + 4 >= text.len or text[i] != '^') return null;
    if (std.mem.eql(u8, text[i .. i + 5], "^Cs0;")) return 0;
    if (std.mem.eql(u8, text[i .. i + 5], "^Cs1;")) return 1;
    if (std.mem.eql(u8, text[i .. i + 5], "^Cs2;")) return 2;
    if (std.mem.eql(u8, text[i .. i + 5], "^Cs3;")) return 3;
    return null;
}

/// glyph index 0..58 for an ASCII char, exactly game.go's tileIndex.
fn tileOf(c: u8) i16 {
    if (c < ' ' or c > 'Z') return 0;
    return @as(i16, c - ' ');
}

/// One non-control character per slot, control codes dropped: the tile arrays'
/// length.  Precomputed so the arrays below are sized exactly.
pub const GLYPH_COUNT = blk: {
    @setEvalBranchQuota(6 * SOURCE.len);
    var n: usize = 0;
    var i: usize = 0;
    while (i < SOURCE.len) {
        if (controlAt(SOURCE, i)) |_| {
            i += 5;
        } else {
            n += 1;
            i += 1;
        }
    }
    break :blk n;
};

pub const Change = struct { pos: u16, size: u2 };

pub const CHANGE_COUNT = blk: {
    @setEvalBranchQuota(6 * SOURCE.len);
    var n: usize = 0;
    var i: usize = 0;
    while (i < SOURCE.len) {
        if (controlAt(SOURCE, i)) |_| {
            n += 1;
            i += 5;
        } else i += 1;
    }
    break :blk n;
};

/// Where each "^CsN;" lands (game.go preAnalyzeFontChanges).
pub const CHANGES: [CHANGE_COUNT]Change = blk: {
    @setEvalBranchQuota(6 * SOURCE.len);
    var out: [CHANGE_COUNT]Change = undefined;
    var c: usize = 0;
    var pos: u16 = 0;
    var i: usize = 0;
    while (i < SOURCE.len) {
        if (controlAt(SOURCE, i)) |size| {
            out[c] = .{ .pos = pos, .size = size };
            c += 1;
            i += 5;
        } else {
            pos += 1;
            i += 1;
        }
    }
    break :blk out;
};

/// tiles[size][slot] = glyph index, or -1 for a space/passive slot
/// (game.go rebuildText, default-active only for size 0, then textTiles).
pub const TILES: [4][GLYPH_COUNT]i16 = blk: {
    @setEvalBranchQuota(10 * SOURCE.len);
    var out: [4][GLYPH_COUNT]i16 = undefined;
    for (0..4) |size| {
        var active = size == 0;
        var slot: usize = 0;
        var i: usize = 0;
        while (i < SOURCE.len) {
            if (controlAt(SOURCE, i)) |s| {
                active = s == size;
                i += 5;
                continue;
            }
            const c = SOURCE[i];
            out[size][slot] = if (active and c != ' ') tileOf(c) else -1;
            slot += 1;
            i += 1;
        }
    }
    break :blk out;
};
