// --------------------------------------------------------------------------
// The Empire's CABAL cracktro text (EMP_CABL.PRG, TEXT+$2FE1..$332F, 847
// bytes, read by the typewriter at TEXT+$2EEC), byte for byte. Its codes:
// $00 a new line, $FE / $FC reverse video on / off, $F7 a pause and a new
// page, $FF the end (a new page and the text again), $01 n / $02 n the cursor
// n cells left / right one at a time; anything else is a character ($82 = é).
//
// PATCHED to fit the game, as a cracker would patch it: the game's title
// "CABAL" reads "RICK DANGEROUS". Nothing else is changed. ORIGINAL is kept
// for the harness, which checks the typewriter against the original's screens
// as Hatari shows them.
// --------------------------------------------------------------------------
const std = @import("std");

pub const ORIGINAL =
    "*** THE EMPIRE ***\x01\x12\x02\x12 PRESENTS\x00" ++
    "CABAL\x00" ++
    "CRACKED/TRAINER\x00" ++
    "BY \xfeIllegal\xfc from the fallen angels\x00" ++
    "THE EMPIRE IS COMPOSED OF :\x00" ++
    "-The fallen angels (HI HANK!)\x00" ++
    "-The marvellous V8\x00" ++
    "-Nokturnal\x00" ++
    "\x00" ++
    "\xfe                                         \xfc\x00" ++
    "\xf7The \xfeGREETINGS\xfc go to :\x00" ++
    "\xfeMACHINE\x01\x06-CODER\xfc,\xfeEQUINOX\xfc,HOTLINE\x00" ++
    "BBC\x00" ++
    "-EDITMAN\x00" ++
    "another >> Batman edit ? <<<\x00" ++
    "-CLOGGY\x00" ++
    "And the others,i do not remember their\x00" ++
    "names ...\x00" ++
    "the >>Further greetings<< go to :\x00" ++
    "The masters,zarathustra,altair\x00" ++
    "krueger,al cool,steprout\x01\x03\x02\x03\x01\x03\x02\x03\x01\x03ate .\x00" ++
    "patouf ( ma jolie\x01\x03\x02\x03\x01\x03\x02\x03\x01\x03\x02\x03 poup\x82e gonflable )\x00" ++
    "The pleasure greetings go to :\x00" ++
    "Innercircle,German alliance for their\x00" ++
    "demos (it's cool,but why only on 1040?)\x00" ++
    "\xfe                                       \xfc\x00" ++
    "\x00" ++
    "\xfe                                       \xfc\x00" ++
    "\x00" ++
    "\xf7\x00" ++
    "ok let us schlupz now ...\x00" ++
    "\xfe                                       \xfc\x00" ++
    "\x00" ++
    "\xfe                                       \xfc\x00" ++
    "\x00" ++
    "\xff";

const GAME_ORIGINAL = "\x00CABAL\x00";
const GAME_RICK = "\x00RICK DANGEROUS\x00";

pub const RICK = blk: {
    const at = std.mem.indexOf(u8, ORIGINAL, GAME_ORIGINAL).?;
    break :blk ORIGINAL[0..at] ++ GAME_RICK ++ ORIGINAL[at + GAME_ORIGINAL.len ..];
};

comptime {
    std.debug.assert(ORIGINAL.len == 847);
    std.debug.assert(ORIGINAL[ORIGINAL.len - 1] == 0xFF);
    countsNonZero(ORIGINAL);
    countsNonZero(RICK);
}

/// Every $01 n / $02 n has n > 0: the typewriter's `moves -= 1` (cracktro.zig)
/// would wrap on a zero count, and what the 68000 does with one is unknown.
fn countsNonZero(comptime t: []const u8) void {
    @setEvalBranchQuota(10_000);
    var i: usize = 0;
    while (i < t.len) : (i += 1) {
        if (t[i] != 1 and t[i] != 2) continue;
        if (i + 1 >= t.len or t[i + 1] == 0) @compileError("a cursor move with no count");
        i += 1; // the count, not a code
    }
}
