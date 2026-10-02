// Every host test of the glass program (`zig build test`).
test {
    _ = @import("bus.zig");
    _ = @import("sim.zig");
    _ = @import("zmd.zig");
    _ = @import("loader_test.zig");
    _ = @import("keymap.zig");
    _ = @import("pad.zig");
    _ = @import("osd.zig");
    _ = @import("menu.zig");
    _ = @import("shelf.zig");
    _ = @import("evdev.zig");
    _ = @import("devmem.zig");
    _ = @import("app_test.zig");
}
