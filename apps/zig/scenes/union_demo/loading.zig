// --------------------------------------------------------------------------
// The remake's mainMenuLoader (menuloader.js): "NOW LOADING MAIN MENU ... PLEASE
// WAIT WHILE DECOMPRESSING". It stands before the street on the demo's first
// entry (jsApp.preload, main.js) and on every return from a screen
// (MENU_LOADER, main.js:347), so the hub cart shows it on every start: its
// graphics (assets.zig) depack behind that TEX panel (depack fx tex_loader,
// panel apps/zig/assets/screens/union_demo/loader_main_menu.txt, packed in
// build.zig), and the street starts on the frame the last byte lands.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const hw = @import("hardware");
const A = @import("assets.zig");
const DepackFx = @import("depackers").depack_fx.Runner(zg, null); // tex_loader: no tvnoise
const packed_menu = @import("packed_assets").union_demo_menu;

// 133,760 bytes at 5 a line (1,400 a frame) depack in 96 frames; the remake's
// 23x20 panel took 99 (13,820 ms of tween clock at 140 ms a frame).
const BYTES_PER_LINE = 5;

var depack: DepackFx = undefined; // module scope: the runner must not move
var state: State = .failed;
var blob: []u8 = &.{};

const State = enum { loading, done, failed };

/// What the street should do this frame.
pub const Step = enum { loading, ready, running, failed };

fn freeRam(len: usize) ?[]u8 {
    if (hw.hwRamFree() < len) return null;
    const base: usize = hw.hwRamBase() + hw.hwRamUsed();
    return @as([*]u8, @ptrFromInt(base))[0..len];
}

/// Begin depacking behind the panel. Call after the plane's palette is set:
/// the runner restores it when it finishes.
pub fn start(zigos: *zg.ZigOS) void {
    state = .failed;
    blob = freeRam(A.BLOB_LEN) orelse return zg.Console.log("union_demo: no free RAM for the menu graphics", .{});
    if (!depack.start(zigos, packed_menu, blob, BYTES_PER_LINE))
        return zg.Console.log("union_demo: menu graphics unreadable", .{});
    state = .loading;
}

/// Once per frame, before the street updates: .ready exactly once, on the frame
/// the graphics are in (the street's first update), .running after that.
pub fn step(zigos: *zg.ZigOS) Step {
    switch (state) {
        .done => return .running,
        .failed => return .failed,
        .loading => {},
    }
    switch (depack.frame(zigos)) {
        .more => return .loading,
        .done => {
            A.bind(blob);
            state = .done;
            return .ready;
        },
        .failed => {
            zg.Console.log("union_demo: menu graphics depack failed", .{});
            state = .failed;
            return .failed;
        },
    }
}

/// True until the street can draw.
pub fn blocking() bool {
    return state != .done;
}
