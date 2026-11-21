// --------------------------------------------------------------------------
// The ST game's data, as tools/bubblebobble/rip_st.py cut it: the TEXT
// segment's tables and texts (no code) and the GRAPHICS\ files the game
// Fopens (st/tos.zig serves them to its Fread calls).
// --------------------------------------------------------------------------
const tos = @import("st/tos.zig");

const DIR = "../../assets/screens/bubblebobble/";

pub const text = @embedFile(DIR ++ "text.bin");

pub const files = [_]tos.File{
    .{ .name = "BBLOCKS.PI1", .data = @embedFile(DIR ++ "bblocks.pi1") },
    .{ .name = "BUBBLE.SPR", .data = @embedFile(DIR ++ "bubble.spr") },
    .{ .name = "SPIC.PI1", .data = @embedFile(DIR ++ "spic.pi1") },
    .{ .name = "AIRFLOW.DAT", .data = @embedFile(DIR ++ "airflow.dat") },
    .{ .name = "UNSHIFT.SPR", .data = @embedFile(DIR ++ "unshift.spr") },
    .{ .name = "BDATA.DAT", .data = @embedFile(DIR ++ "bdata.dat") },
    .{ .name = "FRUIT.SPR", .data = @embedFile(DIR ++ "fruit.spr") },
    .{ .name = "SECRET.PI1", .data = @embedFile(DIR ++ "secret.pi1") },
    .{ .name = "EXTEND.PI1", .data = @embedFile(DIR ++ "extend.pi1") },
    .{ .name = "DWARF.SPR", .data = @embedFile(DIR ++ "dwarf.spr") },
    .{ .name = "MUSIC.DAT", .data = @embedFile(DIR ++ "music.dat") },
};
