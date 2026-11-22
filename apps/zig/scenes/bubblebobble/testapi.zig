// --------------------------------------------------------------------------
// The headless harness's door into the game (apps/bubblebobble_headless.mjs):
// power on, run whole 50 Hz frames in lockstep with scripted input, read the
// machine back (RAM, the shown screen, the palette, the counters that must
// stay 0). Pulled in only when this scene IS the cart.
// --------------------------------------------------------------------------
const k = @import("st/cpu.zig");
const io = @import("st/io.zig");
const tos = @import("st/tos.zig");
const frame = @import("st/frame.zig");
const present = @import("present.zig");
const sound = @import("sound.zig");
const scene = @import("../bubblebobble.zig");

export fn bbTestPowerOn() void {
    scene.powerOn();
}
/// Run `n` frames; returns the frame count.
export fn bbTestFrames(n: u32) u32 {
    for (0..n) |_| {
        frame.runFrame();
        sound.sync();
    }
    present.latch();
    return @intCast(frame.frames);
}
export fn bbTestJoy(port: u32, state: u32) void {
    frame.setJoystick(@intCast(port & 1), @truncate(state));
}
/// The ACIA byte the VBL reads (a scancode, | $80 released).
export fn bbTestKey(scancode: u32) void {
    io.kbd_byte = @truncate(scancode);
}
/// A key for Crawio (the title's 1 / 2).
export fn bbTestType(ascii: u32) void {
    tos.typeKey(@truncate(ascii));
}
/// RAM (absolute ST address).
export fn bbTestMem() [*]u8 {
    return k.mem.ptr;
}
export fn bbTestBase() u32 {
    return frame.BASE;
}
export fn bbTestShown() u32 {
    return io.shown_base;
}
export fn bbTestPalette() [*]const u16 {
    return &io.palette_top;
}
export fn bbTestRasterCount() u32 {
    return @intCast(io.raster_n);
}
export fn bbTestRasters() [*]const io.RasterWrite {
    return &io.rasters;
}
/// The counters a healthy run keeps at 0: unknown jumps, unmodelled hardware,
/// unanswered TOS calls, interrupt handlers that never returned.
export fn bbTestStat(i: u32) u32 {
    return switch (i) {
        0 => k.bad_pcs,
        1 => k.last_bad,
        2 => io.dropped,
        3 => tos.unknown,
        4 => frame.stuck_irqs,
        5 => @truncate(k.cy),
        6 => io.psg_writes,
        7 => @intFromBool(tos.terminated),
        8 => sound.tunes,
        9 => sound.effects,
        10 => sound.last_tune,
        11 => sound.last_effect,
        12 => io.last_dropped,
        13 => frame.pc,
        14 => present.converted,
        else => 0,
    };
}
/// ZIG mode: the sky colour the HBL gives colour 0 at `line` (0 when off).
export fn bbTestSky(line: u32) u32 {
    return if (present.zig_mode) present.skyAt(line) else 0;
}
/// Run one of the game's routines (TEXT offset) as a subroutine, d0 = `d0`.
export fn bbTestCall(offset: u32, d0: u32) void {
    k.d[0] = d0;
    frame.call(frame.BASE + offset);
}
export fn bbTestPlanePtr() [*]u8 {
    return if (present.plane) |p| p.fb else undefined;
}
export fn bbTestPlaneStride() u32 {
    return if (present.plane) |p| p.stride else 0;
}
