// The GEM 5 engine's native tests, one entry for build.sh's list.
test {
    _ = @import("rect.zig");
    _ = @import("obj.zig");
    _ = @import("find.zig");
    _ = @import("look.zig");
    _ = @import("canvas_test.zig");
    _ = @import("draw_test.zig");
    _ = @import("compose_test.zig");
    _ = @import("tree.zig");
}
