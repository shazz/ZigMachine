// RACER's native tests, rooted at apps/zig so the track binaries (apps/zig/assets) are inside the
// module. scene_tests.zig imports this, so build.sh's native pass runs them; alone:
//   zig test apps/zig/racer_tests.zig
test {
    _ = @import("scenes/racer/trk_test.zig");
    _ = @import("scenes/racer/poly_test.zig");
    _ = @import("scenes/racer/clip_test.zig");
    _ = @import("scenes/racer/xform_test.zig");
    _ = @import("scenes/racer/fix_test.zig");
    _ = @import("scenes/racer/car_test.zig");
    _ = @import("scenes/racer/drive_test.zig");
    _ = @import("scenes/racer/race_test.zig");
}
