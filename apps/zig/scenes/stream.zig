// --------------------------------------------------------------------------
// STREAM — block-streaming a sample off the disk (docs/FLOPPY_DISK.md phase E).
// --------------------------------------------------------------------------
// The disk carries MICROMIX.RAW (signed 8-bit mono @ 12517 Hz) — far bigger than
// the audio ring buffer, so it is NEVER loaded whole. Each frame the scene pulls a
// few 512-byte blocks off the disk via the drive ABI (zg.readBlock) and feeds them
// to the streaming audio ring (zg.audioFeed), paced to the play rate so the ring
// stays full. On screen: the just-streamed waveform + a progress bar. It loops.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;
const Console = zg.Console;

const W: usize = zg.WIDTH; // 320
const H: usize = zg.HEIGHT; // 200
const RATE: f32 = 12517.0; // sample rate (matches the .raw)
const RING: f32 = 32768.0; // the audio ring (STREAM_RING in demo_audio_main.zig)
const RING_BLOCKS: u32 = 64; // 512-byte blocks in one ring

pub const Demo = struct {
    file_block: u32 = 0, // first disk block of the sample data
    total_blocks: u32 = 0, // blocks in the clip
    file_len: u32 = 0, // sample length in bytes
    cur: u32 = 0, // blocks streamed so far (wraps → loops the clip)
    budget: f32 = 0, // fractional byte budget (paces reads to the play rate)
    wave: [512]u8 = [_]u8{128} ** 512, // most-recent streamed block (for display)

    // Parse the flat FAT (v1: file count at $2E4, 32-byte entries from $300) to find
    // MICROMIX.RAW by name — read straight off the disk, the machine reads its own FS.
    fn locateFile(self: *Demo) void {
        const NAME = "MICROMIX.RAW";
        var buf: [512]u8 = undefined;
        _ = zg.readBlock(1, &buf); // block 1 = bytes $200..$3FF (descriptor + first FAT entries)
        const nfiles = std.mem.readInt(u16, buf[0xe4..][0..2], .little); // file count @ $2E4
        var i: usize = 0;
        while (i < nfiles and i < 8) : (i += 1) { // 8 entries fit in this block
            const e = 0x100 + i * 32; // entry i, relative to $200 (disk $300 + i*32)
            if (std.mem.eql(u8, buf[e .. e + NAME.len], NAME)) {
                const start = std.mem.readInt(u32, buf[e + 0x10 ..][0..4], .little);
                const len = std.mem.readInt(u32, buf[e + 0x14 ..][0..4], .little);
                self.file_block = start / 512;
                self.file_len = len;
                self.total_blocks = (len + 511) / 512;
                self.cur = 0;
                Console.log("STREAM: {s} @block {} len {} ({} blocks)", .{ NAME, self.file_block, len, self.total_blocks });
                return;
            }
        }
        Console.log("STREAM: {s} not found on disk", .{NAME});
    }

    // Pull one block off the disk, feed it to the audio ring, keep it for display.
    fn feedBlock(self: *Demo) void {
        var buf: [512]u8 = undefined;
        _ = zg.readBlock(self.file_block + self.cur, &buf);
        const done = self.cur * 512;
        const n: usize = @min(@as(u32, 512), self.file_len - done);
        zg.audioFeed(buf[0..n]);
        @memcpy(self.wave[0..], buf[0..]);
        self.cur += 1;
        if (self.cur >= self.total_blocks) self.cur = 0; // loop the clip
    }

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPaletteEntry(0, Color{ .r = 8, .g = 8, .b = 18, .a = 255 }); // bg
        fb.setPaletteEntry(1, Color{ .r = 80, .g = 220, .b = 255, .a = 255 }); // waveform
        fb.setPaletteEntry(2, Color{ .r = 40, .g = 60, .b = 90, .a = 255 }); // bar track
        fb.setPaletteEntry(3, Color{ .r = 255, .g = 130, .b = 60, .a = 255 }); // bar fill

        self.locateFile();
        zg.audioStreamStart(RATE);
        var i: u32 = 0; // pre-fill ~half the ring so playback starts buffered
        while (i < 32) : (i += 1) self.feedBlock();
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = zigos;
        // The audio clock never stops, so pace by the REAL frame time: a clamped dt
        // left the clip behind the speaker for good at 18 fps or after a hidden tab
        // (apps/stream_pacing_check.mjs).
        self.budget += RATE * @max(elapsed_time, 0) / 1000.0; // bytes the audio consumed since last frame
        // Whole rings of backlog would only lap the ring onto itself: skip them in
        // the clip, then feed what is left — never more than one ring's worth.
        const rings = @floor(self.budget / RING);
        if (rings > 0) {
            if (self.total_blocks > 0) self.cur = @intCast((@as(u64, self.cur) + @as(u64, @intFromFloat(rings)) * RING_BLOCKS) % self.total_blocks);
            self.budget -= rings * RING;
        }
        var guard: u32 = 0;
        while (self.budget >= 512 and guard < RING_BLOCKS) : (guard += 1) {
            self.feedBlock();
            self.budget -= 512;
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = elapsed_time;
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.clearFrameBuffer(0);

        // waveform of the most-recent streamed block (512 samples -> 320 columns)
        var x: usize = 0;
        while (x < W) : (x += 1) {
            const s: i32 = @as(i8, @bitCast(self.wave[x * 512 / W])); // signed -128..127
            const y: usize = @intCast(90 + @divTrunc(s * 70, 128)); // 20..160
            fb.fb[y * W + x] = 1;
        }

        // progress bar (position within the looping clip)
        const prog: usize = if (self.total_blocks == 0) 0 else self.cur * W / self.total_blocks;
        var by: usize = 182;
        while (by < 192) : (by += 1) {
            var bx: usize = 0;
            while (bx < W) : (bx += 1) fb.fb[by * W + bx] = if (bx < prog) 3 else 2;
        }
    }
};
