// --------------------------------------------------------------------------
// The Emlyn Hughes cracktro, generic over its NUMBERS: replicants_emlyn.zig
// runs it on fixed.zig (integers: the default cart, what the FPU-less board
// CPU can afford) and replicants_emlyn_f32.zig on float.zig (the CODEF port's
// algorithm in f32, to measure a single-precision FPU). Everything that is not
// arithmetic — assets, the HBL and its table, the logo sweep, the scroll ring,
// the draw order — is shared, so the two carts show the same screen.
// replicants_emlyn.zig's header describes the screen itself.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const blit = zg.blit;
const zx0 = @import("depackers").zx0;
const packed_assets = @import("packed_assets");

const A = @import("assets.zig");
const rasters = @import("rasters.zig");
const Logo = @import("logo.zig").Logo;
const Scroller = @import("scroller.zig").Scroller;

// The tune is Mad Max's, and the remake plays it as screens/017/zic.ym, a YM
// register dump. This project ships SNDH only, so the dump was matched against
// the archive: zic.ym is LHA-packed and unpacks to SEVEN7.YM, whose YM5 header
// names itself -- "7 Gates of Jambala Level 5" / "Jochen Hippel" (= Mad Max).
// The cracktro simply reused a Hippel GAME tune; nothing here is Emlyn Hughes
// music, and the archive's "Emlyn Hughes Football" (David Whittaker) scores
// 19% against the dump.
//
// Proved by YM register match, not by name: subtune 9 played from its start is
// bit-identical to the dump over all 6784 frames (135.7 s) -- 88192/88192
// registers, zero mismatches, offset 0. Best rival subtune is 49%, which is
// just the noise floor of held/silent registers. The YM title says "Level 5"
// but the SNDH's own ordering puts it at 9; trust the measurement.
// Take the un-flagged file, NOT Mad_Max/Games/SID/ -- that one is ~abdy
// (STE DMA), which loads fine here and plays SILENCE.
const MUSIC = "seven_gates_of_jambala.sndh";
const MUSIC_TUNE: u8 = 9;

const PLANE = 0;
const DIR_FIRE = 5; // the host maps Space AND Enter to input(5)

/// `B` is the cart's number back-end: fixed.zig or float.zig.
pub fn Demo(comptime B: type) type {
    return struct {
        const Self = @This();

        ok: bool,
        images: A.Images,
        logo: Logo(B.Bob),
        scroller: Scroller(B.Curve, B.Mode),
        bars: B.Bars, // the vectorball group and its raster table
        blitter: zg.Blitter, // the logo and the ramp's copies
        started: bool, // go() has drawn once, so the logo may move
        mode: B.Mode, // ORIGINAL or ZIG, and how far between (mode.zig)

        pub fn init(self: *Self, zigos: *ZigOS) void {
            self.ok = false;
            self.started = false;
            self.mode.init();
            self.logo.init();
            self.scroller.init();
            self.bars.init();
            self.blitter.init();

            // On zg.mem, not borrowed above hwRamUsed(): the raster table is in
            // the arena too, and the next allocation would hand a borrow out
            // again. check_fits cannot see these 752 KB (taken at run time), so
            // the free RAM it prints overstates the truth by that much.
            const buf = zg.mem.alloc(u8, A.TOTAL) orelse return fail("no free RAM for the assets");
            if (zx0.depack(packed_assets.replicants_emlyn, buf) == null) return fail("depack failed");
            self.images = A.Images.split(buf);

            // The ST's border is colour 0; black here, so the closed side
            // borders meet the open top and bottom ones.
            zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
            const fb = &zigos.lfbs[PLANE];
            fb.is_enabled = true;
            fb.setPalette(A.palette);
            fb.setPaletteEntry(A.TRANSPARENT, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
            fb.openBorders(.all); // a raster runs edge to edge, so every border opens
            rasters.install(fb); // ... and takes over its HBL, flicker included
            fb.clearFrameBuffer(A.BLACK); // until render() paints the ramp over it
            zg.requestSongTune(MUSIC, MUSIC_TUNE);
            self.ok = true;
        }

        /// No key() and no ownsKeyboard() on purpose: the host maps Space to
        /// input(5) for a cart that does not own the keyboard, and keeps its own
        /// Escape -> menu (demo_main.zig). Declaring key() here would take
        /// Escape away with it and strand the screen.
        pub fn input(self: *Self, dir: u8) void {
            if (dir == DIR_FIRE) self.mode.toggle();
        }

        pub fn update(self: *Self, zigos: *ZigOS, dt: f32) void {
            _ = zigos;
            _ = dt;
            if (!self.ok) return;
            self.bars.turn(); // go() turns the group before drawing
            self.scroller.update();
            if (self.started) self.logo.move(); // ... and moves the logo after
            self.started = true;
            self.mode.update();
        }

        pub fn render(self: *Self, zigos: *ZigOS, dt: f32) void {
            _ = dt;
            if (!self.ok) return;
            // my3d.draw(), split in two: the projection is still three.js's,
            // but what it feeds is the HBL's colour table, not a blit.
            self.bars.build(&self.mode);
            const fb = &zigos.lfbs[PLANE];
            self.ramp(fb);
            // Rasters, then the logo, then the scrolltext — the remake's order.
            // All three take the WHOLE raster now: nothing stops at an edge
            // this screen no longer has.
            self.logo.draw(&self.blitter, fb, self.images.logo);
            self.scroller.draw(blit.Dst.plane(fb), self.images.font, &self.mode);
        }

        /// The bucket ramp under everything, on every one of the 280 rows. The
        /// CPU writes row 0 and the blitter doubles it down the plane (1, 2,
        /// 4 ... rows a copy): nine operations, where 112 KB of CPU copying
        /// cost 0.9 Mc a frame on the board's core.
        fn ramp(self: *Self, fb: *zg.LogicalFB) void {
            @memcpy(fb.fb[0..rasters.row.len], &rasters.row);
            const h: u16 = @intCast(fb.fb_h);
            var done: u16 = 1;
            while (done < h) {
                const n = @min(done, h - done);
                self.blitter.blitCopy(fb, 0, @intCast(done), fb, 0, 0, rasters.row.len, n);
                done += n;
            }
        }
    };
}

fn fail(why: []const u8) void {
    zg.Console.log("replicants_emlyn: {s}", .{why});
}
