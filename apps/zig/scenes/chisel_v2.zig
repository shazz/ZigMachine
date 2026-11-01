// --------------------------------------------------------------------------
// CHISEL v2 — the test cart of the blitter's HW 1.11.0 ops, one mode each:
//
//   key 1  ROTOZOOM  AFFINE spans, one a row (a turning, breathing matrix)
//   key 2  MODE 7    AFFINE spans below a horizon, perspective per row
//   key 3  TUNNEL    MAP: a (u, v) map plus offsets moved every frame
//   key 4  SPRITES   mirrored bobs (MIRROR_X / MIRROR_Y) with the collision bit
//   key 5  FILL      the Amiga area fill (IFE) of a pentagram's edges
//   Escape           back to the menu
//
// The modes cycle by themselves every MODE_FRAMES frames until a key is pressed.
// Every pixel of a mode is drawn by CHISEL (the CPU only lays the fill's edge
// pixels); the machine is the reference, the RTL is proven equal to it
// (fpga/tests/test_rtl_blitter.py). docs/BLITTER_HW_SPEC.md §4.5-4.7.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Console = zg.Console;
const assets = @import("chisel_v2/assets.zig");
const modes = @import("chisel_v2/modes.zig");

const NAMES = [5][]const u8{ "ROTOZOOM", "MODE 7", "TUNNEL", "SPRITES", "FILL" };
const MODE_FRAMES: u32 = 300;
const K_ESC: u32 = 0xE012; // demo_main.zig's code for Escape
const TEXT_COL: u8 = 1;

pub const Demo = struct {
    a: assets.Assets = .{},
    m: modes.Modes = .{},
    mode: u8 = 0,
    auto: bool = true,
    hit: bool = false, // SPRITES: the collision bit after this frame's bobs
    ok: bool = false,
    wants_quit: bool = false,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("chisel_v2 init", .{});
        self.ok = self.a.init() and self.m.init();
        if (!self.ok) Console.log("chisel_v2: no free RAM for the textures", .{});
        const fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPaletteEntry(0, .{ .r = 0, .g = 0, .b = 0, .a = 255 });
        fb.setPaletteEntry(TEXT_COL, .{ .r = 240, .g = 240, .b = 250, .a = 255 });
        fb.setPaletteEntry(2, .{ .r = 40, .g = 70, .b = 140, .a = 255 }); // MODE 7's sky
        for (0..16) |i| { // the texture's ramp
            const k: u8 = @intCast(i * 15);
            fb.setPaletteEntry(@intCast(16 + i), .{ .r = k, .g = 255 - k, .b = @intCast(80 + i * 10), .a = 255 });
        }
        fb.setPaletteEntry(31, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
        fb.setPaletteEntry(assets.SPR_COL, .{ .r = 255, .g = 200, .b = 40, .a = 255 });
        fb.setPaletteEntry(assets.SPR_COL + 1, .{ .r = 200, .g = 60, .b = 40, .a = 255 });
        fb.setPaletteEntry(assets.SPR_COL + 2, .{ .r = 160, .g = 40, .b = 30, .a = 255 });
        fb.setPaletteEntry(assets.SPR_COL + 3, .{ .r = 60, .g = 220, .b = 90, .a = 255 });
        fb.setPaletteEntry(modes.STAR_COL, .{ .r = 230, .g = 90, .b = 220, .a = 255 });
    }

    pub fn setShadeMode(self: *Demo, m: u32) void {
        self.mode = @intCast(@min(m, NAMES.len - 1));
        self.auto = false;
        Console.log("chisel_v2 mode -> {s}", .{NAMES[self.mode]});
    }

    // Declaring key() gives this cart every key (demo_main.zig): Escape is handled here,
    // 1-5 still arrive through setShadeMode.
    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC) self.wants_quit = true;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        self.m.t +%= 1;
        if (self.auto and self.m.t % MODE_FRAMES == 0) self.mode = @intCast((self.mode + 1) % NAMES.len);
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb: *LogicalFB = &zigos.lfbs[0];
        if (!self.ok) return zigos.printText(fb, "NO RAM", 10, 8, TEXT_COL, 0);
        switch (self.mode) {
            0 => self.m.rotozoom(fb, &self.a),
            1 => self.m.mode7(fb, &self.a),
            2 => self.m.tunnel(fb, &self.a),
            3 => self.hit = self.m.sprites(fb, &self.a),
            else => self.m.star(fb),
        }
        zigos.printText(fb, NAMES[self.mode], 10, 8, TEXT_COL, 0);
        if (self.mode == 3) zigos.printText(fb, if (self.hit) "HIT" else "---", 10, zg.HEIGHT - 16, TEXT_COL, 0);
    }
};
