// --------------------------------------------------------------------------
// The demo system's three slots, KESTREL side: command() is what the Falcon's music interrupt
// did on a new 8xx value (load the entry: mode, part, the part's start), tick() is the timer
// slot at the replay's 50 Hz, render() the main slot once a frame. One part runs at a time.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const arena = @import("arena.zig");
const fx = @import("fx.zig");
const scr = @import("screen.zig");
const FLASH_INDEX: u8 = 253; // the flames' palettes use 0, their colours from 1, 255 white
const blobs = @import("blobs.zig");
const text = @import("text.zig");
const ship = @import("ship.zig");
const accents = @import("accents.zig");
const flames = @import("flames.zig");
const chosneck = @import("chosneck.zig");
const credits = @import("credits.zig");
const balloid = @import("balloid.zig");
const finale = @import("finale.zig");
const strobe = @import("strobe.zig");
const art = @import("art.zig");

// The ripped env maps, big-endian on the Falcon, as the rasteriser's little-endian words.
var env_grey: *[4096]u16 = undefined;
var env_orange: *[4096]u16 = undefined;

fn ripped(src: []const u8, dst: *[4096]u16) ?[]const u16 {
    if (src.len != 8192) return null;
    for (dst, 0..) |*w, i| w.* = art.be16(src, i * 2);
    return dst;
}

pub const Show = struct {
    screen: scr.Screen,
    os: *zg.ZigOS,
    border: u16 = 1, // (1: not set yet) the colour the border (the machine's BACKGROUND) shows, 565
    planes: []zg.LogicalFB, // the machine's planes: plane 1 is the flames' 8-bit one
    font: []const u8,
    part: fx.Part = .black,
    part_was: fx.Part = .black,
    painted: u8 = 0, // frames drawn since the command (still pictures are drawn into both buffers)
    blob: blobs.Blobs = .{},
    fade: blobs.Fade = undefined,
    txt: text.Text = .{},
    noise: accents.Noise = .{},
    flash: accents.GreyFlash = .{},
    flame: flames.Flames = .{},
    chos: chosneck.Chosneck = .{},
    cred: credits.Credits = .{},
    ball: balloid.Balloid = undefined,
    thanks: finale.Thanks = .{},
    rg: strobe.Strobe = .{},
    frames50: u32 = 0, // the greetings' frame counter (a Falcon frame = a tick)
    smeared: bool = false, // 825 works once (the Falcon's state $16)
    smear_t: u8 = 0, // 50 Hz ticks since 825 started its smear
    smear_passes: u8 = 0, // feedback passes made so far
    band_frames: u8 = 0, // 829: 824's white band painted into both buffers first
    ticked: bool = false, // a 50 Hz tick ran since the last frame (the feedback passes run at the Falcon's rate)
    on8: bool = false, // the flames' 8-bit plane is the one up: a flash draws there
    clear_frames: u8 = 0, // the ball-oid after a flash: both buffers cleared first (it only clears its box)

    pub fn init(os: *zg.ZigOS) Show {
        initTables();
        credits.initTables();
        blobs.init();
        text.init(os.system_font);
        flames.init(os.system_font);
        chosneck.init(os.system_font);
        balloid.init();
        finale.init(os.system_font);
        strobe.init(os.system_font);
        return .{ .screen = scr.Screen.init(os), .os = os, .planes = &os.lfbs, .font = os.system_font };
    }

    pub fn command(self: *Show, v: u8) void {
        const e = fx.TABLE[v & 63];
        if (e.mode) |m| self.screen.setMode(m);
        self.painted = 0;
        self.part_was = self.part;
        self.part = e.part;
        switch (e.part) {
            .flames => self.on8 = true,
            .white, .white_band, .grey_flash, .hold => {},
            else => self.on8 = false,
        }
        // Parts with their own state word make the next blob command re-init its variant.
        switch (e.part) {
            .blobs, .hold, .grey_flash, .white, .white_band => {},
            else => self.blob.state = 0,
        }
        switch (e.part) {
            .blobs => self.blob.command(v),
            .blob_fade => self.fade = blobs.Fade.start(&self.blob, v == 0x22),
            .text => self.txt = text.Text.start(v),
            .noise => self.noise = .{},
            .flames => self.flame.command(v),
            .strobe => self.rg.restart(),
            .grey_obj => {
                self.ball = balloid.Balloid.start(.grey, ripped(art.env_grey, env_grey));
                self.band_frames = 2;
            },
            .thanks => {
                if (self.part_was != .thanks and self.part_was != .grey_obj) self.ball = balloid.Balloid.start(.grey, ripped(art.env_grey, env_grey));
                self.thanks = .{ .which = @intFromBool(v == 0x3A) };
            },
            .orange => {
                if (self.part_was == .grey_flash or v == 0x2A) self.clear_frames = 2;
                if (v == 0x2A) self.ball = balloid.Balloid.start(.orange, ripped(art.env_orange, env_orange));
                if (v == 0x3B) self.screen.shake = .{ .table = &scr.QUAKE, .axis = .y, .looping = true };
                if (v == 0x3C) self.screen.shake = .{};
            },
            .credits => {
                self.cred.command(v, self.font);
                if (v == 0x33) self.shake(&scr.JOLT, .x);
            },
            .chosneck => if (v == 0x08 and self.part_was != .chosneck) {
                self.chos = .{};
            },
            .grey_flash => self.flash = .{},
            .ship => self.shake(&scr.BOUNCE, .y),
            .smear => if (self.smeared) {
                self.part = .hold;
            } else {
                self.smeared = true;
                self.smear_t = 0;
                self.smear_passes = 0;
                self.shake(&scr.JOLT, .x);
            },
            .jolt => self.shake(&scr.JOLT, .x),
            else => {},
        }
        if (v == 0x07) self.smeared = false;
    }

    fn shake(self: *Show, t: []const i8, axis: scr.Axis) void {
        self.screen.shake = .{ .table = t, .axis = axis };
    }

    /// A 50 Hz tick (the Falcon's VBL / frame). The timer slots run twice: the music interrupt
    /// that calls them is MFP timer D, /200 with a count of 123 = 99.9 Hz (TEXT $50E), not the
    /// replay's 50 Hz.
    pub fn tick(self: *Show) void {
        self.screen.shake.tick();
        self.frames50 +%= 1;
        self.ticked = true;
        self.timerSlot();
        self.timerSlot();
        switch (self.part) {
            .blob_fade => self.fade.tick(),
            .smear => self.smear_t +|= 1,
            .text => self.txt.blurFrame(),
            .credits => self.cred.tick(),
            .grey_obj, .orange, .thanks => self.ball.advance(4), // the ball-oid's clock is 200 Hz
            else => {},
        }
    }

    // The running entry's timer slot, at 100 Hz.
    fn timerSlot(self: *Show) void {
        switch (self.part) {
            .blobs => self.blob.tick(),
            .text => self.txt.count(),
            .noise => self.noise.tick(),
            .grey_flash => {
                self.flash.tick();
                self.flame.tick(); // $6378 walks the flames' offset and the blobs' counters too
                self.blob.tick();
            },
            .flames => self.flame.tick(),
            .chosneck, .chos_blur => self.chos.tick(),
            .strobe => self.rg.tick(),
            .thanks => self.thanks.tick(),
            else => {},
        }
    }

    // On the Falcon the flashes cover the whole raster, border included (the border shows the
    // Videl's colour 0 next to the true-colour picture): here the machine's BACKGROUND register,
    // one store, only when the colour changes.
    fn rgbaOf(c: u16) u32 {
        const r: u32 = (c >> 11) * 255 / 31;
        const g: u32 = ((c >> 5) & 63) * 255 / 63;
        const b: u32 = (c & 31) * 255 / 31;
        return 0xFF00_0000 | b << 16 | g << 8 | r;
    }

    fn setBorder(self: *Show, c: u16) void {
        if (c == self.border) return;
        self.border = c;
        const r: u8 = @intCast((c >> 11) * 255 / 31);
        const g: u8 = @intCast(((c >> 5) & 63) * 255 / 63);
        const b: u8 = @intCast((c & 31) * 255 / 31);
        self.os.setBackgroundColor(.{ .r = r, .g = g, .b = b, .a = 255 });
    }

    // The flashes (823 white, 824 white, 81A/81B the grey ramp): the colour this frame, or null.
    fn flashColour(self: *const Show) ?u16 {
        return switch (self.part) {
            .white, .white_band => 0xFFFF,
            .grey_flash => accents.grey(self.flash.i),
            else => null,
        };
    }

    // EVERY flash goes through here: the whole raster in one colour, the screen and the border
    // together (the Falcon's flash covers both: the border shows its colour 0). The screen side
    // stays on the plane that is up: on the flames' 8-bit plane, one palette entry filled once and
    // then only recoloured (a store a frame, no double-buffer frame of lag behind the border); on
    // the true-colour plane, a fill. 824 fills the 200 lines too: its letterbox-only band left a
    // black frame inside the white border.
    fn drawFlash(self: *Show, c: u16) void {
        self.setBorder(c);
        const first = self.painted == 0;
        self.painted +|= 1;
        if (self.on8) {
            const p8 = self.screen.eightBit(self.planes, true);
            p8.palette[FLASH_INDEX] = rgbaOf(c);
            if (first) @memset(p8.fb[0 .. scr.W * scr.H], FLASH_INDEX);
            return;
        }
        _ = self.screen.eightBit(self.planes, false);
        self.screen.back().fill(c);
        self.screen.flip();
    }

    // The border outside the flashes: the colour the picture's empty area shows. The Falcon's
    // true-colour border is its colour 0, never written, so black throughout; but the blobs'
    // 821 (inverted LUT) and 822 (pushed to the LUT's top) turn the whole picture white, and a
    // white picture in a black border reads as a flash whose border missed it (Matt, 13 Nov).
    // So the border follows the blob LUT's entry for an empty sum: black for every other blob
    // picture, as before. A held frame keeps the border it had.
    fn backdrop(self: *const Show) u16 {
        return switch (self.part) {
            .blobs => self.blob.backdrop(),
            .blob_fade => self.fade.backdrop(),
            .hold => if (self.border == 1) 0 else self.border,
            else => 0,
        };
    }

    // 825's feedback pass: one every SMEAR_EVERY ticks, SMEAR_PASSES in all, then the frame holds.
    // The Hatari capture shows the picture change every 6th frame from 40.68 s to 41.88 s:
    // 11 passes (a 64,000-pixel pass costs the 030 ~6 VBLs on the Falcon's bus). One pass a
    // KESTREL frame blurred 36 times in 0.6 s: far too strong, then frozen (Matt, 13 Nov).
    const SMEAR_EVERY = 6;
    const SMEAR_PASSES = 11;
    fn smearDue(self: *const Show) bool {
        return self.smear_passes < SMEAR_PASSES and self.smear_t >= SMEAR_EVERY * @as(u16, self.smear_passes);
    }

    pub fn render(self: *Show) void {
        if (self.flashColour()) |c| return self.drawFlash(c);
        self.setBorder(self.backdrop());
        const p8 = self.screen.eightBit(self.planes, self.part == .flames);
        if (self.part == .flames) return self.flame.draw(p8);
        const fb = self.screen.back();
        const still = self.painted >= 2; // both buffers hold the still picture
        self.painted +|= 1;
        const ticked = self.ticked;
        self.ticked = false;
        switch (self.part) {
            .hold, .jolt => return self.screen.commit(),
            .smear => {
                if (!self.smearDue()) return self.screen.commit();
                self.smear_passes += 1;
                accents.smear(fb, self.screen.front());
            },
            .black, .other => {
                if (still) return self.screen.commit();
                fb.fill(0);
            },
            .white, .white_band, .grey_flash => unreachable, // drawFlash
            .ship => {
                if (still) return self.screen.commit();
                ship.paint(fb, self.font);
            },
            .noise => self.noise.draw(fb),
            .blobs => self.blob.draw(fb),
            .blob_fade => self.fade.draw(fb),
            .text => self.txt.draw(fb),
            .flames => unreachable, // drawn on plane 1 above
            .chosneck => self.chos.draw(fb),
            .credits => self.cred.draw(fb, self.screen.front()),
            .grey_obj => {
                // 829 clears only the ball's box (x 160..319, lines 25..175): the white on its left
                // is 824's band, left in the Falcon's buffers. 824 drew on the flames' 8-bit plane
                // here, so the true-colour buffers get the band before the first ball.
                if (self.band_frames > 0) {
                    fb.fill(0);
                    accents.white(fb, 25, 175);
                    self.band_frames -= 1;
                }
                self.ball.draw(fb.pixels, fb.stride);
            },
            .thanks => {
                self.thanks.draw(fb);
                self.ball.draw(fb.pixels, fb.stride);
            },
            .orange => {
                if (self.clear_frames > 0) {
                    fb.fill(0);
                    self.clear_frames -= 1;
                }
                self.ball.draw(fb.pixels, fb.stride);
                finale.drawGreets(fb, self.frames50);
            },
            .melt => {
                // A full-screen pass took the 030 about three VBLs: one pass every third tick
                // keeps the capture's pace (the ball still dim 5 s on).
                if (!ticked or self.frames50 % 3 != 0) return self.screen.commit();
                finale.melt(fb, self.screen.front());
            },
            .strobe => self.rg.draw(fb),
            .chos_blur => chosneck.blur(fb, self.screen.front()),
            .chos_zoom => chosneck.zoom(fb, self.screen.front()),
        }
        self.screen.flip();
    }
};

/// The big tables from the arena (once, at init).
pub fn initTables() void {
    env_grey = arena.take([4096]u16);
    env_orange = arena.take([4096]u16);
}
