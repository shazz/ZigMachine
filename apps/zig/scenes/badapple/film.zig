// --------------------------------------------------------------------------
// BAD APPLE!! the player the three carts share (166 spans, 167 tiles, 168 polygons): the film file streamed off
// the floppy a 1 s block ahead (blocks.zig), the 30 fps clock, the palette, failure, the local song.
// `Codec` is the format: MAGIC, FILE (its name on the disk), MAX_PACKED / MAX_RAW (its largest block), and a
// State with reset(), beginBlock(raw) ?usize (the offset of the block's first frame, after any preamble such
// as the tiles' dictionary) and decodeFrame(bytes, fb, stride) bool (paints plane 0's 8-bit buffer).
//   - One plane, palette 0 black, 1 white (a fade or a tint is a palette write), 2 red = failure.
//   - Sync: the film frame is the elapsed hostMicros since the song was asked for x fps (there is no audio
//     position for a cart-asked song); a late picture decodes every frame it owes (deltas) and shows the last.
//     No clock (a host answering 0): 30 fps off the 60 Hz VBLs. No float anywhere.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const opts = @import("cart_opts");
const blocks = @import("blocks.zig");

const Color = zg.Color;

extern fn hostMicros() u32;

const PLANE: usize = 0;
/// The local song, embedded only with -Dbadapple_music (the file is git-ignored; without the option nothing is read).
const SONG: []const u8 = if (opts.badapple_music) @embedFile("../../assets/screens/badapple/local.xm") else &.{};
const US_PER_S: u64 = 1_000_000;

pub fn Film(comptime Codec: type) type {
    return struct {
        const Self = @This();

        state: Codec.State,
        loader: blocks.Loader,
        block: ?*const blocks.Slot,
        off: usize,
        rem: u16, // frames left in the current block
        shown: u32, // frames decoded so far
        vbls: u32,
        last_us: u32,
        elapsed_us: u64,
        use_clock: bool,
        failed: bool,

        pub fn init(self: *Self, zigos: *zg.ZigOS) void {
            self.state.reset();
            self.block = null;
            self.off = 0;
            self.rem = 0;
            self.shown = 0;
            self.vbls = 0;
            self.elapsed_us = 0;
            self.failed = false;
            self.last_us = hostMicros();
            self.use_clock = self.last_us != 0;

            zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
            const fb = &zigos.lfbs[PLANE];
            fb.is_enabled = true;
            fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
            fb.setPaletteEntry(1, Color{ .r = 255, .g = 255, .b = 255, .a = 255 });
            fb.setPaletteEntry(2, Color{ .r = 224, .g = 0, .b = 0, .a = 255 });
            fb.clearFrameBuffer(0);

            self.loader = blocks.Loader.open(Codec.FILE, Codec.MAGIC, Codec.MAX_PACKED, Codec.MAX_RAW) orelse
                return self.fail(fb);
            if (SONG.len > 0) _ = zg.requestSongBytes(SONG, .xm, 0);
        }

        /// Fail loud: the whole picture goes red (palette entry 2) and the film stops.
        fn fail(self: *Self, fb: *zg.LogicalFB) void {
            self.failed = true;
            fb.clearFrameBuffer(2);
        }

        pub fn update(self: *Self, zigos: *zg.ZigOS, dt: f32) void {
            _ = zigos;
            _ = dt;
            if (self.failed) return;
            self.vbls +|= 1;
            if (self.use_clock) {
                const now = hostMicros();
                self.elapsed_us += now -% self.last_us;
                self.last_us = now;
            }
            // A read-ahead failure is kept in the loader and shown only when the picture reaches that block.
            _ = self.loader.pump(blocks.STEP);
        }

        /// The film frame the clock says is on screen now (0-based, one past the last frame shown when due).
        fn due(self: *const Self) u32 {
            const total = self.loader.header.total_frames;
            if (!self.use_clock) return @min(total, (self.vbls + 1) / 2);
            return @intCast(@min(total, self.elapsed_us * self.loader.header.fps / US_PER_S + 1));
        }

        pub fn render(self: *Self, zigos: *zg.ZigOS, dt: f32) void {
            _ = dt;
            if (self.failed) return;
            const fb = &zigos.lfbs[PLANE];
            const target = self.due();
            while (self.shown < target) {
                if (!self.nextFrame(fb)) return self.fail(fb);
            }
        }

        /// Decodes the next frame of the stream into the plane (taking the next block when this one is spent).
        fn nextFrame(self: *Self, fb: *zg.LogicalFB) bool {
            if (self.rem == 0) {
                const blk = self.loader.takeBlock() orelse return false;
                self.block = blk;
                self.off = self.state.beginBlock(blk.raw[0..blk.len]) orelse return false;
                self.rem = blk.frames;
            }
            const blk = self.block.?;
            if (self.off + 2 > blk.len) return false;
            const flen = @as(usize, blk.raw[self.off]) | (@as(usize, blk.raw[self.off + 1]) << 8);
            self.off += 2;
            if (self.off + flen > blk.len) return false;
            const fb_len = @as(usize, fb.stride) * fb.fb_h;
            if (!self.state.decodeFrame(blk.raw[self.off..][0..flen], fb.fb[0..fb_len], fb.stride)) return false;
            self.off += flen;
            self.rem -= 1;
            self.shown += 1;
            return true;
        }
    };
}
