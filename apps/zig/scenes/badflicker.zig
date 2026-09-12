// --------------------------------------------------------------------------
// BAD FLICKER — the overscan trick done WRONG, by hand.
// --------------------------------------------------------------------------
// A teaching scene. It opens (tries to open) the borders the low-level way:
// instead of calling the zigos helper `fb.flickerBorder()`, it pokes the sealed
// video registers DIRECTLY from the app (raw `@import("hardware")` writes — the
// authentic ST "flip the resolution register" instruction sequence).
//
// And it does it BADLY: the per-plane HBL is registered at the WRONG column (not
// OVERSCAN_MAGIC_X), so every scanline's flicker MISSES the magic timing. The
// machine still sees the flicker (the latch is bumped) but, off the magic column,
// it renders GARBAGE in the border region instead of opening it cleanly — exactly
// like botching the cycle on real hardware. Result: a clean 320x200 window with
// animated low/medium-res-looking noise spilling into all four borders.
//
// Fix it by registering the handler at `zg.OVERSCAN_MAGIC_X` (see fullscreen.zig).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const hw = @import("hardware"); // raw sealed-video ABI — poke registers by hand

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;
const Console = zg.Console;

const PW: usize = zg.PHYSICAL_WIDTH; // 400
const PH: usize = zg.PHYSICAL_HEIGHT; // 280
const BAD_COL: u16 = 200; // deliberately off OVERSCAN_MAGIC_X (40) -> flicker misses

// --- raw register access (no zigos helper) --------------------------------
inline fn regBase() usize {
    return @intCast(hw.hwVideoBase());
}
inline fn poke8(off: usize, v: u8) void {
    @as(*volatile u8, @ptrFromInt(regBase() + off)).* = v;
}
inline fn latchBump() void {
    const p: *volatile u16 = @ptrFromInt(regBase() + hw.REG_RES_FLICKER);
    p.* = p.* +% 1;
}

// Per-plane HBL: do the resolution flicker BY HAND, every scanline. Registered at
// BAD_COL, so the machine sees the flicker off-column and paints border garbage.
fn handler_badflicker(_: *LogicalFB, _: *ZigOS, _: u16, _: u16) void {
    poke8(hw.REG_RESOLUTION, hw.RES_MEDIUM); // the ST poke: flip to medium...
    poke8(hw.REG_RESOLUTION, hw.RES_PLANES); // ...and straight back to low
    latchBump(); // tell the (untrappable) machine a flicker happened this line
}

pub const Demo = struct {
    name: u8 = 0,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("badflicker init — raw poke, wrong column, expect garbage borders", .{});
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setOverscanBuffer();

        var palette: [256]Color = undefined;
        for (&palette, 0..) |*c, i| {
            const v: u8 = @intCast(i);
            c.* = .{ .r = v, .g = v *% 2, .b = v *% 3, .a = 255 };
        }
        fb.setPalette(palette);

        // A smooth ramp across the whole 400x280 buffer: the visible window shows
        // it cleanly; the borders would show it too IF the trick were timed right.
        var y: usize = 0;
        while (y < PH) : (y += 1) {
            var x: usize = 0;
            while (x < PW) : (x += 1) fb.fb[y * PW + x] = @truncate(x + y);
        }

        // The trick, done badly (wrong column) -> garbage in the borders.
        fb.setFrameBufferHBLHandler(BAD_COL, handler_badflicker);
        _ = self;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = self;
        _ = zigos;
        _ = elapsed_time;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = self;
        _ = zigos;
        _ = elapsed_time;
    }
};
