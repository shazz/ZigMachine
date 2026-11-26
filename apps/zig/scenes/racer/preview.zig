// --------------------------------------------------------------------------
// RACER: what the track select shows of a track it has not loaded (M5 finish). Step 4's cursor loaded
// the whole file under it (read, depack, CRC, parse: ~0.47 s a press on the board) for four things: the
// racing line's outline, the lap length, the race clock and the name. The library now takes them once,
// at its scan (library.Library.previewAll: each file through the same `load`), and keeps them here, so
// moving the cursor costs nothing and a track is loaded only when it is picked. A file the loader
// refuses is refused at the scan, by name and reason, as before. Integer only. No ZigOS import.
// --------------------------------------------------------------------------
const std = @import("std");
const clock = @import("clock.zig");
const minimap = @import("minimap.zig");
const trk = @import("trk.zig");

pub const BOX = [2]u8{ 136, 70 }; // the select's outline box (seldraw.MAP's w, h)

pub const Preview = struct {
    map: minimap.Map = .{}, // the racing line fitted into BOX
    lap_m: u32 = 0,
    parts: clock.Parts = .{}, // the clock's inputs: the clock itself is computed when shown (clock.break_flat is a run-time key)
    name: [24]u8 = .{0} ** 24, // the file's track name (upper-cased when shown)
    bench_only: bool = false, // the mood's BENCH_ONLY: no race here
    ready: bool = false, // false: no preview (a refused file)

    /// The preview of a parsed track.
    pub fn of(t: *const trk.Track) Preview {
        return .{
            .map = minimap.Map.fit(t, BOX[0], BOX[1]),
            .lap_m = clock.lapLength(t),
            .parts = clock.parts(t),
            .name = t.name,
            .bench_only = t.mood.flags & trk.BENCH_ONLY != 0,
            .ready = true,
        };
    }

    pub fn clk(self: *const Preview) clock.Clock {
        return clock.fromParts(self.parts);
    }

    pub fn label(self: *const Preview) []const u8 {
        return std.mem.sliceTo(&self.name, 0);
    }
};
