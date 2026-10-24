// --------------------------------------------------------------------------
// STNICCC 2000 — the flat-shaded flight from Oxygene's Atari ST demo (2000),
// streamed off its own floppy, with a twist (Matt, 2026-09-13): ten seconds at
// the original 256x200, slow down, rewind to the first frame, "LET'S GO
// FULLSCREEN!", then the whole flight again on the 400x280 overscan screen.
//
// The stream is 1800 pre-projected frames of 2D polygons, 16 colours out of the
// ST's 512. It is VECTOR data, so fullscreen re-rasterizes the polygons at the
// bigger size rather than scaling pixels. It lives on the disk as SCENE1.BIN and
// is read one 64 KB block at a time, as the ST loaded it. The rewind works
// because stniccc/player.zig can redraw any frame by replaying from the last
// frame that clears the screen, or from a keyframe it kept on the way forward
// (stniccc/snaps.zig: a replay is up to ~100 frames, seconds on the board).
//
// Data: scene1.bin, the demo's own stream (MIT notice in
// assets/screens/stniccc/LICENSE.txt). Music: see MUSIC below.
// Credit for the scene belongs to Oxygene.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const st = @import("stniccc/stream.zig");
const player_mod = @import("stniccc/player.zig");
const snaps_mod = @import("stniccc/snaps.zig");
const gpu = @import("stniccc/gpu.zig");
const palette_mod = @import("stniccc/palette.zig");

const ZigOS = zg.ZigOS;
const Color = zg.Color;
const LogicalFB = zg.LogicalFB;

const PLANE: usize = 0;
const SCENE_FILE = "SCENE1.BIN";
// Music source: chcknbnk.mod (found by Matt, 2026-10-19), an Amiga ProTracker module, so no
// SNDH was looked for. The original STNICCC 2000 streamed its music from disk as a packed
// sample stream (the AIFF); Matt accepts this module in its place. It replaces the earlier
// stand-in "STNICCC 2000++" by Dolby (SNDH). The disk carries no audio stream (SCENE1.BIN
// only). The choreography counts VBLs, never audio time, so the tune's length moves no
// sync point (the music loops under the flight).
const MUSIC = "chcknbnk.mod";
const SMALL_OX: usize = (zg.WIDTH - player_mod.SRC_W) / 2; // centred on the 320-wide screen

const BLACK: u8 = 16; // outside the scene's 16 colours
const RED: u8 = 17; // the border when the disk has no SCENE1.BIN, or it fails to decode
const WHITE: u8 = 18;

// --- the choreography ---
const SMALL_FRAMES: u32 = 600; // 10 s at 60 fps, one stream frame per VBL
const SLOW_FRAMES: u32 = 150; // 2.5 s easing to a stop
const REWIND_ACCEL: f32 = 0.08; // stream frames per VBL, gained every VBL
const REWIND_MAX: f32 = 8;
const MESSAGE_FRAMES: u32 = 180; // 3 s
const BLINK: u32 = 30; // the message blinks every half second
const MESSAGE = "LET'S GO FULLSCREEN!";
const ZOOM_FRAMES: u32 = 90; // 1.5 s easing the 256x200 window out to the whole 400x280 plane

// Smoothstep. A linear zoom starts and stops abruptly; easing both ends is what
// reads as a camera pull rather than a jump cut. Clamped, so the last frame is
// exactly the full plane and the centring subtractions below cannot underflow.
fn ease(x: f32) f32 {
    const c = @min(@max(x, 0), 1);
    return c * c * (3 - 2 * c);
}

fn lerp(from: u32, to: u16, k: f32) usize {
    const a: f32 = @floatFromInt(from);
    const b: f32 = @floatFromInt(to);
    return @intFromFloat(a + (b - a) * k);
}

const Act = enum { small, slowing, rewinding, message, zooming, fullscreen, failed };

pub const Demo = struct {
    player: player_mod.Player,
    // The loaded 64 KB block and the player's frame index, from the cart RAM
    // arena (zg.mem) once in init(): as fields of the static cart they were
    // 130 KB of zeros in the data segment.
    block: *[st.BLOCK]u8,
    index: *player_mod.Index,
    file: zg.disk.Entry,
    act: Act,
    t: u32, // VBLs since the act began (1 on its first frame)
    pos: f32, // the stream frame to show, fractional while speeding and slowing
    speed: f32,
    wide: bool, // the plane has been switched to the overscan screen
    pal: palette_mod.Palette, // entries 0..15 as shown

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        // The Demo arrives as stale bytes on a re-entry from the menu: assign all.
        self.act = .small;
        self.t = 0;
        self.pos = 0;
        self.speed = 1;
        self.wide = false;
        self.pal.reset(); // the loop below paints every entry black
        self.block = zg.mem.mustAlloc(u8, st.BLOCK)[0..st.BLOCK];
        self.index = &zg.mem.mustAlloc(player_mod.Index, 1)[0];
        // The ST's border is colour 0: black, so the closed borders of the small
        // phase match the black bars beside the 256-wide window.
        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        for (0..256) |i| fb.setPaletteEntry(@intCast(i), Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        fb.setPaletteEntry(RED, Color{ .r = 255, .g = 0, .b = 0, .a = 255 });
        fb.setPaletteEntry(WHITE, Color{ .r = 255, .g = 255, .b = 255, .a = 255 });
        gpu.clearPlane(fb.fb[0 .. @as(usize, fb.stride) * fb.fb_h], fb.stride, fb.fb_h, BLACK);
        const lay = zg.disk.mount() orelse return self.fail(fb);
        self.file = zg.disk.find(lay, SCENE_FILE) orelse return self.fail(fb);
        self.player.init(.{ .ctx = self, .readFn = readDiskBlock }, self.block, self.index);
        const snaps = &zg.mem.mustAlloc(snaps_mod.Snaps, 1)[0];
        snaps.init(zg.mem.mustAlloc(u8, snaps_mod.POOL_BYTES));
        self.player.snaps = snaps; // until the rewind is over: nothing seeks back after it
        zg.requestSong(MUSIC);
    }

    // One 64 KB block of SCENE1.BIN, pulled off the floppy 512 bytes at a time.
    fn readDiskBlock(ctx: *anyopaque, index: u32, dst: *[st.BLOCK]u8) usize {
        const self: *Demo = @ptrCast(@alignCast(ctx));
        const start = @as(u64, index) * st.BLOCK;
        if (start >= self.file.len) return 0;
        const n: u32 = @intCast(@min(st.BLOCK, self.file.len - start));
        const part = zg.disk.Entry{ .start = self.file.start + @as(u32, @intCast(start)), .len = n, .kind = self.file.kind };
        return zg.disk.read(part, dst[0..n]);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = zigos;
        _ = elapsed_time;
        self.t +|= 1;
        switch (self.act) {
            .small, .fullscreen => self.pos = @floatFromInt(self.t - 1),
            .slowing => {
                self.speed = 1 - @as(f32, @floatFromInt(self.t)) / SLOW_FRAMES;
                self.pos += @max(self.speed, 0);
            },
            .rewinding => {
                self.speed = @max(self.speed - REWIND_ACCEL, -REWIND_MAX);
                self.pos = @max(self.pos + self.speed, 0);
            },
            .message, .zooming, .failed => {},
        }
        switch (self.act) {
            .small => if (self.t >= SMALL_FRAMES) self.enter(.slowing),
            .slowing => if (self.t >= SLOW_FRAMES) self.enter(.rewinding),
            .rewinding => if (self.pos == 0) self.enter(.message),
            .message => if (self.t >= MESSAGE_FRAMES) self.enter(.zooming),
            .zooming => if (self.t >= ZOOM_FRAMES) self.enter(.fullscreen),
            .fullscreen, .failed => {},
        }
    }

    fn enter(self: *Demo, act: Act) void {
        self.act = act;
        self.t = 0;
        if (act == .rewinding) self.speed = 0;
        if (act == .message) self.player.snaps = null; // no more keyframes to keep or use
        if (act == .fullscreen) {
            self.pos = 0;
            self.player.shown = null; // the zoom left frame 0 drawn at its own rect
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = elapsed_time;
        const fb = &zigos.lfbs[PLANE];
        switch (self.act) {
            .failed => return,
            .message => {
                if (self.t % BLINK != 1) return;
                self.player.shown = null; // redraw frame 0, which also erases the text
                self.drawFrame(fb) catch return self.fail(fb);
                if ((self.t / BLINK) % 2 == 0) zigos.printText(fb, MESSAGE, messageX(), 140, WHITE, BLACK);
            },
            .zooming => {
                if (!self.wide) self.goFullscreen(fb); // borders open FIRST: the margin is black anyway
                // No whole-plane clear a frame: the view only GROWS (eased, centred), so last
                // frame's rect lies inside this one, and frame 0 clears its own rect (its
                // flags byte is $07). Outside it the plane is still goFullscreen's black.
                self.player.shown = null; // the rect moved, so frame 0 is redrawn every frame
                self.drawFrame(fb) catch self.fail(fb);
            },
            .fullscreen => {
                if (!self.wide) self.goFullscreen(fb);
                self.drawFrame(fb) catch self.fail(fb);
            },
            else => self.drawFrame(fb) catch self.fail(fb),
        }
    }

    fn messageX() i16 {
        return @intCast(SMALL_OX + (player_mod.SRC_W - MESSAGE.len * 8) / 2);
    }

    fn goFullscreen(self: *Demo, fb: *LogicalFB) void {
        fb.openBorders(.all); // a 400x280 overscan plane, every border open
        gpu.clearPlane(fb.fb[0 .. @as(usize, fb.stride) * fb.fb_h], fb.stride, fb.fb_h, 0);
        self.wide = true;
        self.player.shown = null;
    }

    fn drawFrame(self: *Demo, fb: *LogicalFB) st.Error!void {
        // Wrap by subtraction: pos advances by at most REWIND_MAX a VBL, so this equals @mod
        // (a libm fmod routine every frame) exactly.
        const total: f32 = @floatFromInt(self.player.total);
        if (self.player.total != 0) while (self.pos >= total) : (self.pos -= total) {};
        const n: u32 = @intFromFloat(self.pos);
        if (self.player.shown == n) return;
        try self.player.show(n, self.view(fb));
        self.pal.apply(fb, self.player.palette(n));
    }

    fn view(self: *const Demo, fb: *LogicalFB) player_mod.View {
        const px = fb.fb[0 .. @as(usize, fb.stride) * fb.fb_h];
        if (self.act == .zooming) return self.zoomView(fb);
        // Fills are CPU word stores (stniccc/span.zig); gpu.begin hooks CHISEL in for big ones.
        if (self.wide) return .{ .target = gpu.begin(.{ .px = px, .stride = fb.stride, .w = fb.fb_w, .h = fb.fb_h, .ox = 0 }), .w = fb.fb_w, .h = fb.fb_h };
        return .{
            .target = gpu.begin(.{ .px = px, .stride = fb.stride, .w = player_mod.SRC_W, .h = player_mod.SRC_H, .ox = SMALL_OX }),
            .w = player_mod.SRC_W,
            .h = player_mod.SRC_H,
        };
    }

    // The zoom out of the small window. Both rects are CENTRED, so at t = 0 this
    // reproduces exactly where the 256x200 window sat once the borders opened the
    // plane to 400x280 — the switch has no jump, it just starts growing. The
    // stream is vectors, so every step re-rasterizes the polygons at the new size;
    // nothing is resampled and the edges stay as crisp as the small window's.
    fn zoomView(self: *const Demo, fb: *LogicalFB) player_mod.View {
        const k = ease(@as(f32, @floatFromInt(self.t)) / @as(f32, @floatFromInt(ZOOM_FRAMES)));
        const w = lerp(player_mod.SRC_W, fb.fb_w, k);
        const h = lerp(player_mod.SRC_H, fb.fb_h, k);
        const oy = (@as(usize, fb.fb_h) - h) / 2;
        // polyfill.Target has an ox but no oy: start the slice oy rows in instead.
        const px = fb.fb[oy * @as(usize, fb.stride) ..][0 .. @as(usize, fb.stride) * h];
        return .{
            .target = gpu.begin(.{ .px = px, .stride = fb.stride, .w = w, .h = h, .ox = (@as(usize, fb.fb_w) - w) / 2 }),
            .w = @intCast(w),
            .h = @intCast(h),
        };
    }

    // Fail loud: no disk, no SCENE1.BIN, or a corrupt stream stops the scene with a red screen.
    fn fail(self: *Demo, fb: *LogicalFB) void {
        self.act = .failed;
        gpu.clearPlane(fb.fb[0 .. @as(usize, fb.stride) * fb.fb_h], fb.stride, fb.fb_h, RED);
    }
};
