// --------------------------------------------------------------------------
// RACER: what the cart prints for the benchmark (bench.zig has the line formats): the CSV every
// 32 frames, and on a scripted lap the view's CRC-32 every 60 script frames plus the summary at the
// lap's end (the CRC is a real frame's cost once a second, outside avg_us: switch it off with c). A CRC needs the plane quiet: CHISEL is synced first. Nothing here touches the picture.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const bench = @import("bench.zig");
const cam = @import("cam.zig");
const xf = @import("xform.zig");

pub const Where = struct { script: u32, scripted: bool, lap_frames: u32 = cam.LAP_FRAMES };

pub const Reporter = struct {
    frames: u32 = 0,
    crc_xor: u32 = 0,
    crc_on: bool = true, // key c: the CRC reads the whole view once a second (~0.5 Mc): off for the pass-bar runs

    pub fn report(self: *Reporter, os: *zg.ZigOS, fb: *zg.LogicalFB, b: *bench.Bench, k: bench.Knobs, c: bench.Counts, at: Where) void {
        self.frames +%= 1;
        var buf: [200]u8 = undefined;
        if (self.frames % bench.WINDOW == 0) zg.Console.log("{s}", .{b.csv(&buf, self.frames, k, c)});
        if (!at.scripted) return;
        if (self.crc_on and at.script % bench.CRC_EVERY == 0) {
            os.blitSync();
            const crc = viewCrc(fb);
            self.crc_xor ^= crc;
            zg.Console.log("{s}", .{bench.crcLine(&buf, at.script, crc)});
        }
        if (at.script % at.lap_frames == 0) {
            zg.Console.log("{s}", .{b.summary(&buf, k, self.crc_xor)});
            b.resetLap();
            self.crc_xor = 0;
        }
    }
};

fn viewCrc(fb: *zg.LogicalFB) u32 {
    var h = std.hash.crc.Crc32IsoHdlc.init();
    var y: usize = @intCast(xf.Y0);
    while (y < xf.Y1) : (y += 1) h.update(fb.fb[y * fb.stride ..][0..320]);
    return h.final();
}
