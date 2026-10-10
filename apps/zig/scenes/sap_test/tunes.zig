// --------------------------------------------------------------------------
// SAP TEST: the tunes, as their SAP headers give them.
//
// Five Atari 8-bit tunes from ASMA, the Atari SAP Music Archive
// (https://asma.atari.org/), fetched 2026-10-10 and published in docs/music/
// under their ASMA names (Matt, 2026-10-10). prototypes/sap_asma/SOURCES.txt
// holds each file's URL and sha256. Every field below is copied from the
// file's own header (AUTHOR, NAME, DATE, TYPE, NTSC, SONGS, TIME): the screen
// shows what the archive says, it does not parse the file.
// --------------------------------------------------------------------------

pub const Tune = struct {
    file: []const u8, // under docs/music/
    title: []const u8,
    composer: []const u8,
    year: []const u8,
    sap_type: u8, // the TYPE tag: 'B' or 'C' (the player refuses D/S/R)
    pal: bool, // false = the file carries the NTSC tag
    /// One TIME tag per song, so its length is the file's SONGS count.
    times: []const []const u8,
};

pub const TUNES = [_]Tune{
    .{ .file = "Warhawk.sap", .title = "WARHAWK", .composer = "ROB HUBBARD", .year = "1986", .sap_type = 'B', .pal = true, .times = &.{"3:37"} },
    .{ .file = "Gauntlet.sap", .title = "GAUNTLET", .composer = "BEN DAGLISH", .year = "1985", .sap_type = 'B', .pal = true, .times = &.{"0:18"} },
    .{ .file = "Barbarian.sap", .title = "BARBARIAN", .composer = "JAKUB HUSAK", .year = "1993", .sap_type = 'C', .pal = true, .times = &.{"3:48"} },
    // ASMA itself is unsure of this attribution: its AUTHOR tag is "Steve Coleman <?>".
    .{ .file = "Ninja.sap", .title = "NINJA", .composer = "STEVE COLEMAN (?)", .year = "1986", .sap_type = 'B', .pal = false, .times = &.{"0:51"} },
    .{ .file = "BMX_Simulator.sap", .title = "BMX SIMULATOR", .composer = "DAVID WHITTAKER", .year = "1986", .sap_type = 'B', .pal = true, .times = &.{ "6:21", "0:03", "0:03" } },
};

pub const CREDITS =
    "SAP TEST ....  ATARI 8-BIT MUSIC ON THE ZIGMACHINE: EACH TUNE IS ITS OWN 6502 CODE, " ++
    "RUN BY A FROM-SCRATCH 6502 AND PLAYED ON THE MACHINE'S POKEY ....  " ++
    "THE TUNES COME FROM ASMA, THE ATARI SAP MUSIC ARCHIVE - ASMA.ATARI.ORG - THANK YOU TO ITS CREW ....  " ++
    "WARHAWK BY ROB HUBBARD 1986 ....  GAUNTLET BY BEN DAGLISH 1985 ....  " ++
    "BARBARIAN BY JAKUB HUSAK 1993 ....  NINJA BY STEVE COLEMAN (?) 1986 ....  " ++
    "BMX SIMULATOR BY DAVID WHITTAKER 1986 ....  ALL CREDIT TO THE COMPOSERS ....  " ++
    "UP AND DOWN PICK A TUNE, SPACE OR ENTER PLAYS IT, LEFT AND RIGHT CHANGE THE SONG, ESCAPE LEAVES ....        ";
