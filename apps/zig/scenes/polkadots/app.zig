// --------------------------------------------------------------------------
// POLKA DOTS, generic over its NUMBERS: polkadots.zig runs it on fixed.zig
// (integers: the default cart, what the FPU-less board CPU can afford) and
// polkadots_f32.zig on float.zig (the CODEF port's algorithm in f32, to
// measure a single-precision FPU). Everything after the intensity grid — the
// four render modes, the readout, the keys — is shared, so the two carts are
// the same bench. polkadots.zig's header describes the screen itself.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;

const torus = @import("torus.zig");
const shade = @import("shade.zig");
const dots = @import("dots.zig");
const modes = @import("modes.zig");
const readout = @import("readout.zig");

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

/// `B` is the cart's number back-end: fixed.zig or float.zig.
pub fn Demo(comptime B: type) type {
    return struct {
        const Self = @This();

        rotation: B.Rotation,
        mode: modes.Mode,
        blitter: zg.Blitter,
        cost: dots.Cost, // last frame's blitter operations, for the label and the tap
        loads: u32, // halftone pattern changes, mode 2 only
        wants_quit: bool, // demo_main returns to the menu on this

        pub fn init(self: *Self, zigos: *ZigOS) void {
            self.rotation.init();
            self.mode = .dot_size;
            self.cost = .{};
            self.loads = 0;
            self.wants_quit = false;
            self.blitter.init();
            if (!owned) {
                geometry = &zg.mem.mustAlloc(torus.Geometry, 1)[0];
                shade.alloc();
                const mesh = geometry.build();
                B.init(geometry, &mesh);
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

        /// 1..4 pick the renderer, Space cycles, Escape leaves. A screen that
        /// declares key() owns every key, Escape included.
        pub fn key(self: *Self, cp: u32) void {
            if (cp == K_ESC) self.wants_quit = true;
            if (cp >= '1' and cp <= '0' + modes.NAMES.len) self.mode = @enumFromInt(cp - '1');
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
            self.rotation.step(STEP_X, STEP_Y);
            B.render(&self.rotation, &grid);
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
            readout.label(zigos, fb, m, modes.NAMES[m], self.cost.ops, self.cost.px);
            readout.tap(fb, m, self.cost.ops);
        }
    };
}
