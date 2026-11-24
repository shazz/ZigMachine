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
/// Lap v1's input stream: the buttons of the Lua reference's lap from the tick control starts, one byte a tick (tools/racer/phys_fixture.py).
/// The race's player stream (the Lua autopilot, recorded): lap v2's input and the headless race's driver, one byte a race tick.
pub const race_v2: []const u8 = @embedFile("../../assets/screens/racer/race_v2.btn");
pub const lap_v1: []const u8 = @embedFile("../../assets/screens/racer/lap_v1.btn");
