// Every host test of the glass program (`zig build test`).
test {
    _ = @import("bus.zig");
    _ = @import("sim.zig");
    _ = @import("sim_test.zig");
    _ = @import("zmd.zig");
    _ = @import("zmd_test.zig");
    _ = @import("loader_test.zig");
    _ = @import("system_test.zig");
    _ = @import("keymap.zig");
    _ = @import("pad.zig");
    _ = @import("pad_test.zig");
    _ = @import("mouse_test.zig");
    _ = @import("osd.zig");
    _ = @import("menu.zig");
    _ = @import("menu_test.zig");
    _ = @import("shelf.zig");
    _ = @import("config.zig");
    _ = @import("meta.zig");
    _ = @import("stats.zig");
    _ = @import("board_info.zig");
    _ = @import("evdev.zig");
    _ = @import("devmem.zig");
    _ = @import("app_test.zig");
    _ = @import("app_request_test.zig");
    _ = @import("app_stats_test.zig");
    _ = @import("app_shelf_test.zig");
    _ = @import("console_test.zig");
    _ = @import("text.zig");
    _ = @import("page_debug.zig");
    _ = @import("snd_info_test.zig");
    _ = @import("beats.zig");
    _ = @import("ctl_test.zig");
    _ = @import("app_ctl_test.zig");
}
