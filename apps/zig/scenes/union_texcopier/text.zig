// --------------------------------------------------------------------------
// TEX COPIER's lines (screens/texcopier/screen.js:77-119), 41 characters each,
// printed from canvas x 0 in 16-pixel cells: 40 on screen, the 41st past the edge.
// --------------------------------------------------------------------------
const std = @import("std");

pub const LEN = 41;
/// The font's range: initTile(16,14,32) on a 20x3 sheet.
pub const FIRST_CHAR = ' ';
pub const LAST_CHAR = FIRST_CHAR + 60 - 1;

/// this.text[0..33]. The remake never sets text[29]: font.print(undefined) throws
/// inside draw() before the text canvas reaches the screen, so that 7-second slot
/// shows the bare black fill (and in melonJS the throw stops the frame loop for
/// good). null keeps the slot and its timing; it draws nothing.
pub const LINES = [_]?*const [LEN]u8{
    "    COPY-PROGRAM BY 6719 AND MAD MAX     ",
    "        PRESS SPACE TO START COPY        ",
    "WHAT DO YOU THINK ABOUT THIS LITTLE COPY ",
    "    IT'S THE FIRST ONE WITH RASTERS,     ",
    "        AND MUZAK WHILE COPYING          ",
    "   AND IT TELLS YOU A LOT OF CRAP TALK   ",
    "   EXCUSE US FOR NOT USING ANY BORDER    ",
    "   OR FOR ABSENCE OF TRACKING-SPRITES    ",
    " BUT WE WANTED TO READ A WHOLE DISK-SIDE ",
    "             INTO HALF-A-MEG             ",
    " AND THIS MEANS, THAT WE NEED MEMORY !!! ",
    "DO YOU THINK THIS COPY IS A BIT TOO SLOW ",
    "REMEMBER, THIS DISC CONTAINS 900 KB DATA ",
    "          PRETTY MUCH ? YES !!           ",
    "   WE ARE USING A VERY SPECIAL FORMAT    ",
    "AND THAT TAKES IT'S TIME TO FORMAT WRITE ",
    "              AND VERIFY !!              ",
    "  AND, AFTER ALL, YOU SHALL HEAR THAT    ",
    "    FANTASTIC SOUNDTRACK COMPLETELY !    ",
    "  AND NOW SOME OF THE LATEST TEX-NEWS:   ",
    " SOME PEOPLE OF TEX ARE NOW PROFESSIONAL ",
    "             GAME-DESIGNERS              ",
    " OF COURSE WE WON'T SAY AT WHICH COMPANY ",
    "BUT WE ARE SURE YOU'LL RECOGNIZE US..... ",
    "      JUST SEE AND HEAR IF YOU'RE        ",
    "     BUYING NEW GAMES KNOWING THIS       ",
    "    YOU WON'T BE SURPRISED TO HEAR:      ",
    "  TEX WON'T CRACK ANY GAMES NO MORE!     ",
    " BUT DON'T WORRY: IF WE HAVE THE TIME,   ",
    null,
    " WE'LL CONTINUE TO MAKE DEMOS BIT BY BIT ",
    "  OK GUYS, NO MORE SPACE FOR TEXT LEFT.  ",
    "   LET'S START ANEW.  BYE, BYE FOLKS!!   ",
    "                                         ",
};

/// this.copy[0]: once copying, currentText is 0 and nothing changes it again.
/// copy[1..6] (INSERT DESTINATION, READING, WRITING, ALL DONE, PRESS '0', FORMATTING)
/// are never shown by the remake.
pub const COPYING: *const [LEN]u8 = " PLEASE INSERT WRT-PROTECTED SOURCE-DISK ";

comptime {
    @setEvalBranchQuota(20_000);
    for (LINES ++ [_]?*const [LEN]u8{COPYING}) |maybe| if (maybe) |line| for (line) |c| {
        std.debug.assert(c >= FIRST_CHAR and c <= LAST_CHAR);
    };
}
