// GEM 5's program objects (gui/alert_*.zig and what follows): their pure halves' native tests,
// one entry for build.sh's list. At rom/gem/ so the files under gui/ can reach ../engine/.
test {
    _ = @import("gui/alert_art.zig");
    _ = @import("gui/alert_tree.zig");
    _ = @import("desktop/fsel_tree.zig");
}
