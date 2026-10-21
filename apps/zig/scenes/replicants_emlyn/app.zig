// --------------------------------------------------------------------------
// The Emlyn Hughes cracktro, with its NUMBERS switchable live: F runs the
// per-frame maths on fixed.zig (integers: what the FPU-less board CPU can
// afford) or on float.zig (the CODEF port's algorithm in f32), and F again
// switches back. That is the FPU comparison on ONE cart: on a board built with
// the f32 FPU (ZM_FPU=1) the float side runs on it, elsewhere it is soft-float
// and only slower. motion.zig holds what moves, one per number system, and
// swap.zig carries the state across a press. Everything that is not
// arithmetic — assets, the HBL and its table, the ramp, the draw order — is
// shared, so both show the same screen. replicants_emlyn.zig starts on the
// integers, replicants_emlyn_f32.zig on f32; its header describes the screen.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const zx0 = @import("depackers").zx0;
const packed_assets = @import("packed_assets");

const A = @import("assets.zig");
const rasters = @import("rasters.zig");
const dirty = @import("dirty.zig");
const swap = @import("swap.zig");

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
const K_ESC: u32 = 0xE012; // demo_main.zig's code for Escape

/// `start_fpu`: the numbers the cart boots on (F switches them at any time).
pub fn Demo(comptime start_fpu: bool) type {
    return struct {
        const Self = @This();

        ok: bool,
        images: A.Images,
        fixed: swap.Fixed, // what moves, in integers
        float: swap.Float, // ... and in f32: only the `fpu` one runs
        fpu: bool, // the f32 side is the live one
        blitter: zg.Blitter, // the logo and the ramp's copies
        ramp: dirty.Ramp, // where the plane still shows the ramp (dirty.zig)
        started: bool, // go() has drawn once, so the logo may move
        wants_quit: bool, // demo_main's pollCartRequest: back to the menu

        pub fn init(self: *Self, zigos: *ZigOS) void {
            self.ok = false;
            self.started = false;
            self.wants_quit = false;
            self.fpu = start_fpu;
            self.fixed.init();
            self.float.init();
            self.blitter.init();
            self.ramp.init();

            // On zg.mem, not borrowed above hwRamUsed(): the raster table is in
            // the arena too, and the next allocation would hand a borrow out
            // again. check_fits cannot see these 752 KB (taken at run time), so
            // the free RAM it prints overstates the truth by that much.
            const buf = zg.mem.alloc(u8, A.TOTAL) orelse return fail("no free RAM for the assets");
            if (zx0.depack(packed_assets.replicants_emlyn, buf) == null) return fail("depack failed");
            dirty.recode(buf[0 .. A.LOGO_W * A.LOGO_H]);
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

        /// Space still arrives here: the host maps it to input(5) for a cart
        /// that does not own the keyboard (no ownsKeyboard() on purpose).
        pub fn input(self: *Self, dir: u8) void {
            if (dir != DIR_FIRE) return;
            // only the live side: swap.zig carries `zig` across with the rest
            if (self.fpu) self.float.mode.toggle() else self.fixed.mode.toggle();
        }

        /// Declaring key() means this cart gets EVERY key (demo_main.zig), so
        /// Escape is handled here, as blitter_demo's B toggle does.
        pub fn key(self: *Self, cp: u32) void {
            if (cp == K_ESC) self.wants_quit = true;
            if (cp == 'f' or cp == 'F') self.switchNumbers();
            // ZIG's styles (switches.zig); in ORIGINAL they change nothing
            const sw = if (self.fpu) &self.float.mode.sw else &self.fixed.mode.sw;
            if (cp == '1') sw.cycleScroller();
            if (cp == '2') sw.cycleRasters();
        }

        fn switchNumbers(self: *Self) void {
            if (self.fpu) swap.toFixed(&self.float, &self.fixed) else swap.toFloat(&self.fixed, &self.float);
            self.fpu = !self.fpu;
            zg.Console.log("replicants_emlyn: maths in {s}", .{if (self.fpu) "f32 (the FPU)" else "fixed point"});
        }

        pub fn update(self: *Self, zigos: *ZigOS, dt: f32) void {
            _ = zigos;
            _ = dt;
            if (!self.ok) return;
            if (self.fpu) self.float.update(self.started) else self.fixed.update(self.started);
            self.started = true;
        }

        pub fn render(self: *Self, zigos: *ZigOS, dt: f32) void {
            _ = dt;
            if (!self.ok) return;
            const fb = &zigos.lfbs[PLANE];
            if (self.fpu) {
                self.float.render(&self.blitter, &self.ramp, fb, &self.images);
            } else {
                self.fixed.render(&self.blitter, &self.ramp, fb, &self.images);
            }
        }
    };
}

fn fail(why: []const u8) void {
    zg.Console.log("replicants_emlyn: {s}", .{why});
}
