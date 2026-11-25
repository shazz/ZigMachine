// --------------------------------------------------------------------------
// BAD APPLE!! (cart 162): a 1-bit film as a stream of ROW-TRANSITION EDITS, our own player (design: docs/ports/badapple).
//   - SPANS.BIN (format "BASP", tools/badapple/spans.py) is on the .zmd floppy and is read one 1 s (30 frame)
//     ZX0 block at a time, a block ahead (badapple/blocks.zig).
//   - A frame is decoded row by row (badapple/decoder.zig); only the rows whose edges moved are repainted, with
//     CPU memsets, into plane 0's 8-bit buffer. Black and white are palette entries 0 and 1, so a fade or a tint
//     is a palette write. No float anywhere: the clock is integer microseconds.
//   - Sync: the film frame is the elapsed hostMicros since the song was asked for x fps (there is no audio
//     position for a cart-asked song: the host's song engine does not report one); a picture behind decodes
//     every frame it owes (edits are deltas, none can be skipped) and shows the last.
//   - The disk on the shelf holds OUR synthetic test film (tools/badapple/synth.py). Matt's own build
//     (-Dbadapple_music, prototypes/cards/build_badapple.sh) swaps in the real stream and the XM, which are
//     never committed.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const opts = @import("cart_opts");
const decoder = @import("badapple/decoder.zig");
const blocks = @import("badapple/blocks.zig");

const ZigOS = zg.ZigOS;
const Color = zg.Color;

extern fn hostMicros() u32;

const PLANE: usize = 0;
const SPANS_FILE = "SPANS.BIN";
/// The local song, embedded only with -Dbadapple_music (the file is git-ignored; without the option nothing is read).
const SONG: []const u8 = if (opts.badapple_music) @embedFile("../assets/screens/badapple/local.xm") else &.{};
const US_PER_S: u64 = 1_000_000;

pub const Demo = struct {
    state: decoder.State,
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

    pub fn init(self: *Demo, zigos: *ZigOS) void {
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

        self.loader = blocks.Loader.open(SPANS_FILE) orelse return self.fail(fb);
        if (SONG.len > 0) _ = zg.requestSongBytes(SONG, .xm, 0);
    }

    /// Fail loud: the whole picture goes red (palette entry 2) and the film stops.
    fn fail(self: *Demo, fb: *zg.LogicalFB) void {
        self.failed = true;
        fb.clearFrameBuffer(2);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
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
    fn due(self: *const Demo) u32 {
        const total = self.loader.header.total_frames;
        if (!self.use_clock) return @min(total, (self.vbls + 1) / 2);
        return @intCast(@min(total, self.elapsed_us * self.loader.header.fps / US_PER_S + 1));
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.failed) return;
        const fb = &zigos.lfbs[PLANE];
        const target = self.due();
        while (self.shown < target) {
            if (!self.nextFrame(fb)) return self.fail(fb);
        }
    }

    /// Decodes the next frame of the stream into the plane (taking the next block when this one is spent).
    fn nextFrame(self: *Demo, fb: *zg.LogicalFB) bool {
        if (self.rem == 0) {
            self.block = self.loader.takeBlock() orelse return false;
            self.off = 0;
            self.rem = self.block.?.frames;
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
