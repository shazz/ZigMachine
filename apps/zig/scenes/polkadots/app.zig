// --------------------------------------------------------------------------
// POLKA DOTS, with its NUMBERS switchable live: F projects, lights and fills
// the torus with shade_fixed.zig (integers: the rewrite that took the board
// from 2 fps to 28) or with shade_f32.zig (the CODEF port's algorithm, kept
// from before that rewrite, in f32 for the FPU), and F again switches back.
// On a board built with the f32 FPU (ZM_FPU=1) the float side runs on it,
// elsewhere it is soft-float and only slower. Everything after the intensity
// grid -- the four render modes, the readout, the keys -- is shared, so it is
// one bench either way; the readout says F32 while the float side is live.
// polkadots.zig boots on the integers, polkadots_f32.zig on f32; replicants_
// emlyn's F is the same switch. polkadots.zig's header describes the screen.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;

const torus = @import("torus.zig");
const shade = @import("shade.zig");
const dots = @import("dots.zig");
const modes = @import("modes.zig");
const readout = @import("readout.zig");
const fixed = @import("shade_fixed.zig");
const float = @import("shade_f32.zig");
const trig = zg.fixtrig;

const PLANE = 0;
const K_ESC: u32 = 0xE012;
const DIR_FIRE = 5; // the host maps Space and Enter to input(5)

// go(): the group turns before every draw (screen.js:110-111).
const STEP_X = 0.02;
const STEP_Y = 0.04;

// The torus comes from the RAM arena (zg.mem), once per cart load: as statics
// it was 25 KB of zeros written into the cart binary.
var geometry: *torus.Geometry = undefined;
var owned = false;
var grid: shade.Grid = undefined;
var palette_scratch: [256]Color = undefined;

/// `start_fpu`: the numbers the cart boots on (F switches them at any time).
pub fn Demo(comptime start_fpu: bool) type {
    return struct {
        const Self = @This();

        rot_fixed: fixed.Rotation, // the turn in integers
        rot_float: float.Rotation, // ... and in f32: only the `fpu` one moves
        fpu: bool, // the f32 side is the live one
        mode: modes.Mode,
        blitter: zg.Blitter,
        cost: dots.Cost, // last frame's blitter operations, for the label and the tap
        loads: u32, // halftone pattern changes, mode 2 only
        wants_quit: bool, // demo_main returns to the menu on this

        pub fn init(self: *Self, zigos: *ZigOS) void {
            self.rot_fixed.init();
            self.rot_float.init();
            self.fpu = start_fpu;
            self.mode = .dot_size;
            self.cost = .{};
            self.loads = 0;
            self.wants_quit = false;
            self.blitter.init();
            if (!owned) {
                geometry = &zg.mem.mustAlloc(torus.Geometry, 1)[0];
                shade.alloc();
                const mesh = geometry.build();
                fixed.init(geometry, &mesh); // fixed first: its tables keep their place
                float.init(geometry, &mesh);
                owned = true;
            }

            const fb = &zigos.lfbs[PLANE];
            fb.is_enabled = true;
            palette_scratch = dots.palette();
            fb.setPalette(palette_scratch);
            fb.clearFrameBuffer(0);
        }

        /// The original is frame-locked (requestAnimFrame), and the increments
        /// are per FRAME, not per second — so the turn belongs in render(), with
        /// the draw it precedes, rather than being scaled by dt here.
        pub fn update(self: *Self, zigos: *ZigOS, dt: f32) void {
            _ = self;
            _ = zigos;
            _ = dt;
        }

        /// 1..4 pick the renderer, Space cycles, F switches the numbers,
        /// Escape leaves. A screen that declares key() owns every key.
        pub fn key(self: *Self, cp: u32) void {
            if (cp == K_ESC) self.wants_quit = true;
            if (cp >= '1' and cp <= '0' + modes.NAMES.len) self.mode = @enumFromInt(cp - '1');
            if (cp == 'f' or cp == 'F') self.switchNumbers();
        }

        /// The turn carried across, so the torus keeps its pose. Float here
        /// runs once a keypress, never a frame.
        fn switchNumbers(self: *Self) void {
            if (self.fpu) {
                self.rot_fixed = .{ .x = trig.fromRadians(self.rot_float.x), .y = trig.fromRadians(self.rot_float.y) };
            } else {
                self.rot_float = .{ .x = trig.toRadians(self.rot_fixed.x), .y = trig.toRadians(self.rot_fixed.y) };
            }
            self.fpu = !self.fpu;
        }

        pub fn input(self: *Self, dir: u8) void {
            if (dir == DIR_FIRE) self.mode = @enumFromInt((@intFromEnum(self.mode) + 1) % modes.NAMES.len);
        }

        /// The host can drive the mode too (the headless harness does), so the
        /// four renderers can be compared without a keyboard.
        pub fn setShadeMode(self: *Self, m: u32) void {
            if (m < modes.NAMES.len) self.mode = @enumFromInt(m);
        }

        pub fn render(self: *Self, zigos: *ZigOS, dt: f32) void {
            _ = dt;
            const fb = &zigos.lfbs[PLANE];
            // shade_f32 is the one INTENTIONAL float-per-frame path: it is
            // there to measure the board's FPU against shade_fixed.
            if (self.fpu) {
                self.rot_float.step(STEP_X, STEP_Y);
                float.render(&self.rot_float, &grid);
            } else {
                self.rot_fixed.step(STEP_X, STEP_Y);
                fixed.render(&self.rot_fixed, &grid);
            }
            // The clear is a FILL like any other, so the halftone pattern mode 2
            // left loaded would dither it. Drop it before clearing, every frame.
            self.blitter.clearHalftone();
            self.blitter.clear(fb, 0);
            self.loads = 0;
            self.cost = switch (self.mode) {
                .dot_size => dots.stamp(fb, &self.blitter, &grid),
                .halftone => modes.halftone(fb, &self.blitter, &grid, &self.loads),
                .solid => modes.solid(fb, &self.blitter, &grid),
                .fill_dots => modes.fillDots(fb, &self.blitter, &grid),
            };
            const m = @intFromEnum(self.mode);
            readout.label(zigos, fb, m, modes.NAMES[m], self.cost.ops, self.cost.px, self.fpu);
            readout.tap(fb, m, self.cost.ops);
        }
    };
}
