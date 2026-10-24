// --------------------------------------------------------------------------
// The street's loader: the remake's mainMenuLoader (menuloader.js), which stands
// before the street on the demo's first entry (jsApp.preload, main.js) and on
// every return from a screen (MENU_LOADER, main.js:347), so the hub cart shows it
// on every start: its graphics (assets.zig) depack behind a TEX panel (depack fx
// tex_loader, packed in build.zig). The panel's text is the Union Demo's FIRST
// loader's, The Carebears' credits (demoloader.js, union_demo_intro/loader_demo.txt):
// the demo has ONE panel between its intro splash and the street (Matt, 2026-10-24).
// On the first entry the landed panel holds until a key ("PRESS ANY KEY TO
// CONTINUE"); a return from a door's screen starts the street when the last byte lands.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const A = @import("assets.zig");
const depackers = @import("depackers");
const tex = depackers.tex_loader;
const DepackFx = depackers.depack_fx.Runner(zg, null); // tex_loader: no tvnoise
const packed_menu = @import("packed_assets").union_demo_menu;

// 133,760 bytes at 5 a line (1,400 a frame) depack in 96 frames; the remake's
// 23x20 panel took 99 (13,820 ms of tween clock at 140 ms a frame).
const BYTES_PER_LINE = 5;

var depack: DepackFx = undefined; // module scope: the runner must not move
var state: State = .failed;
var blob: []u8 = &.{};
var wait_key = false; // hold the landed panel until a key (the demo's first entry)
var pressed = false;

const State = enum { loading, landed, done, failed };

/// What the street should do this frame.
pub const Step = enum { loading, ready, running, failed };

/// Begin depacking behind the panel. Call after the plane's palette is set:
/// the runner restores it when it finishes. `wait`: the panel's text ends "PRESS ANY
/// KEY TO CONTINUE" (The Carebears' credits), so on the demo's first entry the landed
/// panel holds until a key, as demoloader.js did; a return from a door's screen goes on.
pub fn start(zigos: *zg.ZigOS, wait: bool) void {
    state = .failed;
    wait_key = wait;
    pressed = false;
    // On zg.mem, taken once however often this runs: a second start depacks
    // into the same block.
    if (blob.len != A.BLOB_LEN)
        blob = zg.mem.alloc(u8, A.BLOB_LEN) orelse return zg.Console.log("union_demo: no free RAM for the menu graphics", .{});
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
        .landed => {
            if (!pressed) return .loading;
            state = .done;
            return .ready;
        },
        .loading => {},
    }
    switch (depack.frame(zigos)) {
        .more => return .loading,
        .done => {
            A.bind(blob);
            if (wait_key) {
                state = .landed;
                drawLanded(zigos);
                return .loading;
            }
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

/// A key while the landed panel holds (Space, Enter, fire: demoloader.js took any key
/// once every letter had landed). Ignored before: a key during the depack does nothing.
pub fn press() void {
    if (state == .landed) pressed = true;
}

// The runner cleared the plane and gave the street's colours back when the depack
// ended: the panel goes back up whole, in its ink, until the key. The caller sets the
// street's palette again (union_demo.zig startLoader) before the street draws.
fn drawLanded(zigos: *zg.ZigOS) void {
    const fb = &zigos.lfbs[0];
    fb.is_enabled = true;
    fb.setPaletteEntry(0, .{ .r = 0, .g = 0, .b = 0, .a = 0 });
    fb.setPaletteEntry(depackers.depack_fx.TEX_INK, .{ .r = tex.INK.r, .g = tex.INK.g, .b = tex.INK.b, .a = 255 });
    tex.draw(fb, depack.text, depack.cols, tex.timelineEnd(@intCast(depack.text.len)), depackers.depack_fx.TEX_INK);
}
