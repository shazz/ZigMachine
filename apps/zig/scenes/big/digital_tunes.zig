// "DARE TO PRESS:" — the Digital Solution's six entries as the picture prints
// them, and the Mad Max SNDH each one plays. Split out of big/digital.zig the
// way list.zig is split out of screen.zig: the screen's DATA, which the harness
// reads, apart from the screen's drawing.
//
// `label` is not drawn — the picture already carries it — it is here so the
// mapping can be read, checked and reported by name.
//
// The six name five files because Phantom_Of_The_Asteroid.sndh carries ##02:
// PHANTOMS 1 and 2 are its subtunes 1 and 2, not two entries on one tune.
pub const Entry = struct {
    label: []const u8,
    song: []const u8,
    tune: u8, // SNDH subtune, counting from 1
};

pub const TUNES = [6]Entry{
    .{ .label = "1. ACE II", .song = "digital/Ace_2.sndh", .tune = 1 },
    .{ .label = "2. LABELLO", .song = "digital/Labello.sndh", .tune = 1 },
    .{ .label = "3. PHANTOMS 1", .song = "digital/Phantom_Of_The_Asteroid.sndh", .tune = 1 },
    .{ .label = "4. PHANTOMS 2", .song = "digital/Phantom_Of_The_Asteroid.sndh", .tune = 2 },
    .{ .label = "5. SANXION-LOADER", .song = "digital/Sanxion.sndh", .tune = 1 },
    .{ .label = "6. STAR PAWS", .song = "digital/Starpaws.sndh", .tune = 1 },
};
