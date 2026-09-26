// whichpart 2 -- SYNC SCREEN #2 (screen.js do_sync2): the SYNC logo alone,
// flashing to its blue-sky version (sync2.png) while the three voices' summed
// "peak" (vu.zig) is 7 or more. sync1/sync2.png are 2x-doubled, midhandled at
// (320, 51): top-left 640-space (160, 3), so ST (80, 2) showing halved rows Y-2.
const frame = @import("frame.zig");
const assets = @import("assets.zig");
const image = @import("image.zig");
const Vu = @import("vu.zig").Vu;

pub fn step(vu: *Vu, regs: *const [16]u8) void {
    vu.watch(regs);
    const peak = vu.h[0] + vu.h[1] + vu.h[2];
    const img = if (peak >= 7) &assets.sync2 else &assets.sync1;
    var y: i32 = 2;
    while (y < 50) : (y += 1) {
        var x: i32 = 80;
        while (x < 240) : (x += 1) {
            const g = img.at(x - 80, y - 2);
            if (g != image.NONE) frame.put(x, y, g);
        }
    }
    vu.remember(regs);
}
