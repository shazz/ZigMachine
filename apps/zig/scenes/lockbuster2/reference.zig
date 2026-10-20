// --------------------------------------------------------------------------
// The planar reference engine (engine.zig) inside the cart, for the harness
// only: apps/lockbuster2_headless.mjs steps it in lockstep with the shown
// chunky engine and compares the plane pixel for pixel, so the proof covers
// the REAL blitter (machine-video.wasm's hwBlit), not just the native test's
// array backend. Nothing in the cart's own frame calls it: its ~0.5 MB of ring
// is taken from zg.mem on the harness's first call, never on the board.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const engine_mod = @import("engine.zig");

var ref: engine_mod.Engine = undefined;
var ready = false;

/// The reference screen (the original's 32000 planar bytes) at engine tick
/// `tick`; null when zg.mem cannot hold the reference or `tick` is behind it.
pub fn screenAt(tick: usize) ?[]const u8 {
    if (!ready) {
        const a = zg.mem.alloc(u8, engine_mod.BUFFER_BYTES) orelse return null;
        const b = zg.mem.alloc(u8, engine_mod.BUFFER_BYTES) orelse return null;
        const h0 = zg.mem.alloc(u8, engine_mod.HEADER_BYTES) orelse return null;
        const h1 = zg.mem.alloc(u8, engine_mod.HEADER_BYTES) orelse return null;
        const c = zg.mem.alloc(u8, engine_mod.COMPILED_BYTES) orelse return null;
        ref.init(.{ a, b }, .{ h0, h1 }, c);
        ready = true;
    }
    if (ref.tick > tick) return null;
    while (ref.tick < tick) ref.step();
    return ref.screen();
}
