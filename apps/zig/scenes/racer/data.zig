// --------------------------------------------------------------------------
// RACER: the two tracks' binaries (tools/racer/trackc.py from tools/racer/gen_track.py, committed
// under apps/zig/assets/screens/racer/; tools/tests/test_racer_trackc.py checks the files are what
// the generator and converter write today). Copied into aligned arrays at compile time: a
// misaligned load traps on the board. No ZigOS import: the native tests read them too.
// --------------------------------------------------------------------------
const OVAL_RAW = @embedFile("../../assets/screens/racer/oval.ktrk");
const CITY_RAW = @embedFile("../../assets/screens/racer/city.ktrk");
const oval_blob: [OVAL_RAW.len]u8 align(16) = OVAL_RAW.*;
const city_blob: [CITY_RAW.len]u8 align(16) = CITY_RAW.*;
pub const oval: []align(4) const u8 = &oval_blob;
pub const city: []align(4) const u8 = &city_blob;
