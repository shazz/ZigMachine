// The B.I.G. Demo's jukebox list: TEX's own 116 menu entries, exactly as they
// stand in CODEF screen 23 (screen.js:89-204), and the SNDH each one plays.
//
// The remake names a .ym per entry ("Big - Delta  7.ym"). Those dumps are Mad
// Max's Best-In-Galaxy tunes, and the archive holds the real SNDH images, so a
// "<Tune> N.ym" is <Tune>.sndh subtune N (they match 1:1 — Aufweidersehen Monty
// is 13 .ym files and a 13-subtune SNDH, Delta 10 and 10, and so on). The file
// names differ from TEX's spelling in places (Confusion -> Confuzion, W.a.r ->
// Make_Love_Not_W_A_R): that is the archive's naming, not a substitution.
//
// `song = ""` means "select it, nothing plays" — which is what the original
// does for its four separator rows, and all we can honestly do for the four
// entries with no SNDH behind them (see the scene header).
pub const Entry = struct {
    label: []const u8, // 34 or 35 chars, printed with the 8x8 list font
    song: []const u8, // "" = nothing to play
    tune: u8, // SNDH subtune, counting from 1
};

pub const ENTRIES = [_]Entry{
    .{ .label = "----------TOP OF LIST--------------", .song = "", .tune = 0 },
    .{ .label = "                                   ", .song = "", .tune = 0 },
    .{ .label = "               ACE 2               ", .song = "big/Ace_2.sndh", .tune = 1 },
    .{ .label = "     AUFWIEDERSEHEN MONTY  #1     ", .song = "big/Aufweidersehen_Monty.sndh", .tune = 1 },
    .{ .label = "     AUFWIEDERSEHEN MONTY  #2     ", .song = "big/Aufweidersehen_Monty.sndh", .tune = 2 },
    .{ .label = "     AUFWIEDERSEHEN MONTY  #3     ", .song = "big/Aufweidersehen_Monty.sndh", .tune = 3 },
    .{ .label = "     AUFWIEDERSEHEN MONTY  #4     ", .song = "big/Aufweidersehen_Monty.sndh", .tune = 4 },
    .{ .label = "     AUFWIEDERSEHEN MONTY  #5     ", .song = "big/Aufweidersehen_Monty.sndh", .tune = 5 },
    .{ .label = "     AUFWIEDERSEHEN MONTY  #6     ", .song = "big/Aufweidersehen_Monty.sndh", .tune = 6 },
    .{ .label = "     AUFWIEDERSEHEN MONTY  #7     ", .song = "big/Aufweidersehen_Monty.sndh", .tune = 7 },
    .{ .label = "     AUFWIEDERSEHEN MONTY  #8     ", .song = "big/Aufweidersehen_Monty.sndh", .tune = 8 },
    .{ .label = "     AUFWIEDERSEHEN MONTY  #9     ", .song = "big/Aufweidersehen_Monty.sndh", .tune = 9 },
    .{ .label = "     AUFWIEDERSEHEN MONTY #10     ", .song = "big/Aufweidersehen_Monty.sndh", .tune = 10 },
    .{ .label = "     AUFWIEDERSEHEN MONTY #11     ", .song = "big/Aufweidersehen_Monty.sndh", .tune = 11 },
    .{ .label = "     AUFWIEDERSEHEN MONTY #12     ", .song = "big/Aufweidersehen_Monty.sndh", .tune = 12 },
    .{ .label = "     AUFWIEDERSEHEN MONTY #13     ", .song = "big/Aufweidersehen_Monty.sndh", .tune = 13 },
    .{ .label = "       BALLOON CHALLENGE #1       ", .song = "big/Balloon_Challange.sndh", .tune = 1 },
    .{ .label = "         BATTLE OF BRITAIN         ", .song = "big/Battle_Of_Britain.sndh", .tune = 1 },
    .{ .label = "         BUMP SET SPIKE #1         ", .song = "big/Bump_Set_And_Spike.sndh", .tune = 1 },
    .{ .label = "         BUMP SET SPIKE #2         ", .song = "big/Bump_Set_And_Spike.sndh", .tune = 2 },
    .{ .label = "            CHIMERA #1            ", .song = "big/Chimera.sndh", .tune = 1 },
    .{ .label = "            CHIMERA #2            ", .song = "big/Chimera.sndh", .tune = 2 },
    .{ .label = "   CLUMSY COLIN ACTION BIKER #1   ", .song = "big/Clumsy_Colin_Action_Biker.sndh", .tune = 1 },
    .{ .label = "   CLUMSY COLIN ACTION BIKER #2   ", .song = "big/Clumsy_Colin_Action_Biker.sndh", .tune = 2 },
    .{ .label = "   CLUMSY COLIN ACTION BIKER #3   ", .song = "big/Clumsy_Colin_Action_Biker.sndh", .tune = 3 },
    .{ .label = "        COMMANDO #1 - GAME        ", .song = "big/Commando.sndh", .tune = 1 },
    .{ .label = "      COMMANDO #2 - HIGHSCORE      ", .song = "big/Commando.sndh", .tune = 2 },
    .{ .label = "            COMMANDO #3            ", .song = "big/Commando.sndh", .tune = 3 },
    .{ .label = "             CONFUSION             ", .song = "big/Confuzion.sndh", .tune = 1 },
    .{ .label = "          CRAZY COMETS #1          ", .song = "big/Crazy_Comets.sndh", .tune = 1 },
    .{ .label = "          CRAZY COMETS #2          ", .song = "big/Crazy_Comets.sndh", .tune = 2 },
    .{ .label = "       DELTA  #1 - HIGHSCORE       ", .song = "big/Delta.sndh", .tune = 1 },
    .{ .label = "         DELTA  #2 - TITLE         ", .song = "big/Delta.sndh", .tune = 2 },
    .{ .label = "             DELTA  #3             ", .song = "big/Delta.sndh", .tune = 3 },
    .{ .label = "             DELTA  #4             ", .song = "big/Delta.sndh", .tune = 4 },
    .{ .label = "             DELTA  #5             ", .song = "big/Delta.sndh", .tune = 5 },
    .{ .label = "             DELTA  #6             ", .song = "big/Delta.sndh", .tune = 6 },
    .{ .label = "             DELTA  #7             ", .song = "big/Delta.sndh", .tune = 7 },
    .{ .label = "             DELTA  #8             ", .song = "big/Delta.sndh", .tune = 8 },
    .{ .label = "             DELTA  #9             ", .song = "big/Delta.sndh", .tune = 9 },
    .{ .label = "             DELTA #10             ", .song = "big/Delta.sndh", .tune = 10 },
    .{ .label = "           DELTA PREVIEW           ", .song = "", .tune = 0 },
    .{ .label = "             EDUCATION             ", .song = "big/Education.sndh", .tune = 1 },
    .{ .label = "           FLASH GORDON           ", .song = "big/Flash_Gordon.sndh", .tune = 1 },
    .{ .label = "            FORMULA ONE            ", .song = "big/Formula_1.sndh", .tune = 1 },
    .{ .label = "     GEOFF CAPES STRONGMAN #1     ", .song = "big/Geoff_Capes_Strongman.sndh", .tune = 1 },
    .{ .label = "     GEOFF CAPES STRONGMAN #2     ", .song = "big/Geoff_Capes_Strongman.sndh", .tune = 2 },
    .{ .label = "     GEOFF CAPES STRONGMAN #3     ", .song = "big/Geoff_Capes_Strongman.sndh", .tune = 3 },
    .{ .label = "     GEOFF CAPES STRONGMAN #4     ", .song = "big/Geoff_Capes_Strongman.sndh", .tune = 4 },
    .{ .label = "     GEOFF CAPES STRONGMAN #5     ", .song = "big/Geoff_Capes_Strongman.sndh", .tune = 5 },
    .{ .label = "     GEOFF CAPES STRONGMAN #6     ", .song = "big/Geoff_Capes_Strongman.sndh", .tune = 6 },
    .{ .label = "         GERRY THE GERM #1         ", .song = "big/Gerry_The_Germ.sndh", .tune = 1 },
    .{ .label = "        GERRY THE GERM ##2        ", .song = "big/Gerry_The_Germ.sndh", .tune = 2 },
    .{ .label = "         GERRY THE GERM #3         ", .song = "big/Gerry_The_Germ.sndh", .tune = 3 },
    .{ .label = "         GERRY THE GERM #4         ", .song = "big/Gerry_The_Germ.sndh", .tune = 4 },
    .{ .label = "         GERRY THE GERM #5         ", .song = "big/Gerry_The_Germ.sndh", .tune = 5 },
    .{ .label = "         GERRY THE GERM #6         ", .song = "big/Gerry_The_Germ.sndh", .tune = 6 },
    .{ .label = "         GERRY THE GERM #7         ", .song = "big/Gerry_The_Germ.sndh", .tune = 7 },
    .{ .label = "       GREMLIN MUSIC DEMO #1       ", .song = "big/Gremlin_Music_Demo.sndh", .tune = 1 },
    .{ .label = "       GREMLIN MUSIC DEMO #2       ", .song = "big/Gremlin_Music_Demo.sndh", .tune = 2 },
    .{ .label = "       GREMLIN MUSIC DEMO #3       ", .song = "big/Gremlin_Music_Demo.sndh", .tune = 3 },
    .{ .label = "       GREMLIN MUSIC DEMO #4       ", .song = "big/Gremlin_Music_Demo.sndh", .tune = 4 },
    .{ .label = "       GREMLIN MUSIC DEMO #5       ", .song = "big/Gremlin_Music_Demo.sndh", .tune = 5 },
    .{ .label = "       GREMLIN MUSIC DEMO #6       ", .song = "big/Gremlin_Music_Demo.sndh", .tune = 6 },
    .{ .label = "       GREMLIN MUSIC DEMO #7       ", .song = "big/Gremlin_Music_Demo.sndh", .tune = 7 },
    .{ .label = "    HARVEY SMITHS SHOW JUMPING    ", .song = "big/Harvey_Smiths_Show_Jumping.sndh", .tune = 1 },
    .{ .label = "           HUMAN RACE #1           ", .song = "big/Human_Race.sndh", .tune = 1 },
    .{ .label = "           HUMAN RACE #2           ", .song = "big/Human_Race.sndh", .tune = 2 },
    .{ .label = "           HUMAN RACE #3           ", .song = "big/Human_Race.sndh", .tune = 3 },
    .{ .label = "           HUMAN RACE #4           ", .song = "big/Human_Race.sndh", .tune = 4 },
    .{ .label = "           HUMAN RACE #5           ", .song = "big/Human_Race.sndh", .tune = 5 },
    .{ .label = "           HUNTER PATROL           ", .song = "big/Hunter_Patrol.sndh", .tune = 1 },
    .{ .label = "              I-BALL              ", .song = "big/I-Ball.sndh", .tune = 1 },
    .{ .label = "      INTERNATIONAL KARATE +      ", .song = "big/International_Karate_Plus.sndh", .tune = 1 },
    .{ .label = "       INTERNATIONAL KARATE       ", .song = "big/International_Karate.sndh", .tune = 1 },
    .{ .label = "              LABELLO              ", .song = "big/Labello.sndh", .tune = 1 },
    .{ .label = "            LIGHTFORCE            ", .song = "big/Lightforce.sndh", .tune = 1 },
    .{ .label = "            LOCOMOTION            ", .song = "big/Locomotion.sndh", .tune = 1 },
    .{ .label = "        MASTER OF MAGIC #1        ", .song = "big/Master_Of_Magic.sndh", .tune = 1 },
    .{ .label = "        MASTER OF MAGIC #2        ", .song = "big/Master_Of_Magic.sndh", .tune = 2 },
    .{ .label = "        MASTER OF MAGIC #3        ", .song = "big/Master_Of_Magic.sndh", .tune = 3 },
    .{ .label = "        MONTY ON THE RUN #1        ", .song = "big/Monty_On_The_Run.sndh", .tune = 1 },
    .{ .label = "        MONTY ON THE RUN #2        ", .song = "big/Monty_On_The_Run.sndh", .tune = 2 },
    .{ .label = "        MONTY ON THE RUN #3        ", .song = "big/Monty_On_The_Run.sndh", .tune = 3 },
    .{ .label = "        NEMESIS THE WARLOCK        ", .song = "big/Nemesis_The_Warlock.sndh", .tune = 1 },
    .{ .label = "       ONE MAN AND HIS DROID       ", .song = "big/One_Man_and_His_Droid.sndh", .tune = 1 },
    .{ .label = "    PHANTOMS OF THE ASTEROID #1    ", .song = "big/Phantom_Of_The_Asteroid.sndh", .tune = 1 },
    .{ .label = "    PHANTOMS OF THE ASTEROID #2    ", .song = "big/Phantom_Of_The_Asteroid.sndh", .tune = 2 },
    .{ .label = "    SAMANTHA FOX STRIP POKER #1    ", .song = "big/Sam_Fox_Strip_Poker.sndh", .tune = 1 },
    .{ .label = "    SAMANTHA FOX STRIP POKER #2    ", .song = "big/Sam_Fox_Strip_Poker.sndh", .tune = 2 },
    .{ .label = "    SAMANTHA FOX STRIP POKER #3    ", .song = "big/Sam_Fox_Strip_Poker.sndh", .tune = 3 },
    .{ .label = "    SAMANTHA FOX STRIP POKER #4    ", .song = "big/Sam_Fox_Strip_Poker.sndh", .tune = 4 },
    .{ .label = "    SAMANTHA FOX STRIP POKER #5    ", .song = "big/Sam_Fox_Strip_Poker.sndh", .tune = 5 },
    .{ .label = "    SAMANTHA FOX STRIP POKER #6    ", .song = "big/Sam_Fox_Strip_Poker.sndh", .tune = 6 },
    .{ .label = "         SANXION - LOADER         ", .song = "big/Sanxion_Loader.sndh", .tune = 1 },
    .{ .label = "              SANXION              ", .song = "big/Sanxion_Title.sndh", .tune = 1 },
    .{ .label = "            SMALL TITLE            ", .song = "big/Small_Title.sndh", .tune = 1 },
    .{ .label = "            SPELLBOUND            ", .song = "big/Spellbound.sndh", .tune = 1 },
    .{ .label = "            STARPAWS #1            ", .song = "big/Starpaws.sndh", .tune = 1 },
    .{ .label = "            STARPAWS #2            ", .song = "big/Starpaws.sndh", .tune = 2 },
    .{ .label = "            STARPAWS #3            ", .song = "big/Starpaws.sndh", .tune = 3 },
    .{ .label = "             THALAMUS             ", .song = "", .tune = 0 },
    .{ .label = "          THE LAST V8 #1          ", .song = "big/The_Last_V8.sndh", .tune = 1 },
    .{ .label = "          THE LAST V8 #2          ", .song = "", .tune = 0 },
    .{ .label = "          THE LAST V8 #3          ", .song = "", .tune = 0 },
    .{ .label = "         THING ON A SPRING         ", .song = "big/Thing_On_A_Spring.sndh", .tune = 1 },
    .{ .label = "              THRUST              ", .song = "big/Thrust.sndh", .tune = 1 },
    .{ .label = "              WARHAWK              ", .song = "big/Warhawk.sndh", .tune = 1 },
    .{ .label = "               W.A.R               ", .song = "big/Make_Love_Not_W_A_R.sndh", .tune = 1 },
    .{ .label = "              WIZ #1              ", .song = "big/Wiz.sndh", .tune = 1 },
    .{ .label = "              WIZ #2              ", .song = "big/Wiz.sndh", .tune = 2 },
    .{ .label = "              WIZ #3              ", .song = "big/Wiz.sndh", .tune = 3 },
    .{ .label = "               ZOIDS               ", .song = "big/Zoids.sndh", .tune = 1 },
    .{ .label = "              ZOOLOOK              ", .song = "big/Zoolook.sndh", .tune = 1 },
    // The REAL demo's list ends the songs with this row, and selecting it opens
    // the Digital Solution sound-test screen (see big/digital.zig). It has no
    // tune, exactly like the list's separator rows, so the music path treats it
    // as the no-op it is; big_demo.zig watches for its INDEX instead.
    //
    // The CODEF remake DROPPED it — its list runs ZOIDS / ZOOLOOK / blank /
    // "END OF LIST" and stops. We follow the real demo (Matt, 2026-09-19); the
    // divergence is written up in the scene header.
    //
    // It goes HERE, after the last song and before the trailing blank + END OF
    // LIST, and not at the very end: `curent` is clamped to ENTRIES.len - 3, so
    // an entry appended after those two would never be reachable. Put here, the
    // clamp lands exactly on it — which is how the clamp and the list agree.
    .{ .label = "    -:THE DIGITAL DEPARTMENT:-    ", .song = "", .tune = 0 },
    .{ .label = "                                   ", .song = "", .tune = 0 },
    .{ .label = "----------END OF LIST--------------", .song = "", .tune = 0 },
};

/// The row that opens the Digital Solution: the last one `curent` can reach.
pub const DIGITAL: usize = ENTRIES.len - 3;

comptime {
    if (ENTRIES[DIGITAL].song.len != 0) @compileError("the Digital Department row must have no tune");
    if (ENTRIES[DIGITAL].label[4] != '-') @compileError("DIGITAL does not point at the Digital Department row");
}
