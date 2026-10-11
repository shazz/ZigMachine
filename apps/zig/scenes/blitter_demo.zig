// --------------------------------------------------------------------------
// Blitter demo — a rotating vector cube drawn entirely through the sealed 2D
// blitter (docs/BLITTER_HW_SPEC.md), switchable between seven modes that exercise
// the hardware's fill / minterm / halftone / block-copy paths:
//
//   key 1  FLAT      one solid COLOR per face (painter's sort)
//   key 2  LIT       per-face flat lighting (palette recomputed each frame)
//   key 3  HALFTONE  ordered-dither shading (COLOR/BG via the halftone register)
//   key 4  GLENZ     additive OR minterm + a bit-combo palette = see-through
//                    "glenz vectors" (all faces drawn, overlaps blend)
//   key 5  RUBBER    render once, strip-blit back with a per-row sine offset
//                    (bitmap deformation via H one-row BLITs)
//   key 6  TILE      render one small cube, block-copy it across an overlapping
//                    grid (the whole screen for one rasterisation; cost = pixels)
//   key 7  DELAY     video-feedback grid: a ring of the last DN tiles, each cell
//                    showing the cube from N frames ago (a trail through time)
//
// The scene owns only the mesh, rotation and palette; the machine owns the fill
// rule (the sealed ethos). Plane 0 displays; planes 1 (ring) and 2 (tile) are
// borrowed as blitter scratch. Index 0 = transparent. The parts live in
// blitter_demo/: geom.zig (cube + palette), effects.zig (the seven modes),
// gfx.zig (who draws) and soft.zig (the CPU's blitter).
//
//   key B    draw with CHISEL (BLITTER, the default) or with ZIGGY (CPU): the
//            same pixels either way, so only the frame rate changes (F11 on the
//            board's OSD). The bottom-right corner says which is drawing.
//   Escape   back to the menu.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Console = zg.Console;
const geom = @import("blitter_demo/geom.zig");
const fx = @import("blitter_demo/effects.zig");

const NAMES = [7][]const u8{ "FLAT", "LIT", "HALFTONE", "GLENZ", "RUBBER", "TILE", "DELAY" };
const MODE_MAX: u32 = 6;
const K_ESC: u32 = 0xE012; // demo_main.zig's code for Escape
const LABEL_Y: i16 = zg.HEIGHT - 16; // bottom-right, just inside the 4-px frame

pub const Demo = struct {
    fx: fx.Fx = .{},
    mode: u8 = 0,
    wants_quit: bool = false, // demo_main's pollCartRequest: back to the menu

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("blitter_demo init", .{});
        self.fx.gfx.init();
        self.wants_quit = false;
        const fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPaletteEntry(0, .{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(fx.FRAME_COL, .{ .r = 120, .g = 130, .b = 150, .a = 255 });
        fb.setPaletteEntry(fx.HT_BG, .{ .r = 18, .g = 20, .b = 30, .a = 255 });
        fb.setPaletteEntry(fx.TEXT_COL, .{ .r = 235, .g = 235, .b = 245, .a = 255 });
        zigos.setBackgroundColor(.{ .r = 8, .g = 8, .b = 16, .a = 255 });
        self.fx.gfx.clear(&zigos.lfbs[1], 0); // wipe the DELAY ring (plane 1 scratch)
        self.setShadeMode(0);
    }

    pub fn setShadeMode(self: *Demo, m: u32) void {
        self.mode = @intCast(@min(m, MODE_MAX));
        Console.log("blitter_demo mode -> {s}", .{NAMES[self.mode]});
    }

    // Declaring key() means this cart gets EVERY key (demo_main.zig), so Escape is
    // handled here. 1-7 still arrive through setShadeMode: the cart does not own
    // the keyboard, so the host keeps routing them.
    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC) self.wants_quit = true;
        if (cp == 'b' or cp == 'B') {
            self.fx.gfx.cpu = !self.fx.gfx.cpu;
            Console.log("blitter_demo drawing on the {s}", .{label(self.fx.gfx.cpu)});
        }
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        self.fx.step();
        geom.programPalette(&self.fx.cube, self.mode, &zigos.lfbs[0]);
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb: *LogicalFB = &zigos.lfbs[0];
        self.fx.render(zigos, self.mode);
        zigos.printText(fb, NAMES[self.mode], 10, 8, fx.TEXT_COL, 0);
        const who = label(self.fx.gfx.cpu);
        zigos.printText(fb, who, @intCast(zg.WIDTH - 10 - 8 * who.len), LABEL_Y, fx.TEXT_COL, 0);
    }
};

fn label(cpu: bool) []const u8 {
    return if (cpu) "CPU" else "BLITTER";
}
