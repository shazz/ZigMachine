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
// Playing with the texture modes (chisel_v2/play.zig; the line under the name
// lists the keys of the mode shown):
//   P        the texture: the generated 128 one, or the parrot photo (Adrian
//            Pingstone's scarlet macaw, public domain, assets/screens/parrot/)
//   T        the photo's size, 64 / 128 / 256 (AFFINE and MAP take any power of
//            two up to the 8-bit map's 256; the picture stays the same size)
//   F        pause                X   reset the mode's keys (speeds, zoom, pan...)
//   ROTOZOOM + / - spin (R reverses it), I / O zoom in / out, arrows pan
//   MODE 7   left / right turn, up / down drive (forward / back), + / - camera height
//   TUNNEL   up / down speed (back past 0), left / right roll (R reverses it),
//            B bends the tunnel (its centre on a sine path, 3 strengths, then straight)
//
// The modes cycle by themselves every MODE_FRAMES frames until a key is pressed.
// Every pixel of a mode is drawn by CHISEL (the CPU only lays the fill's edge
// pixels); the machine is the reference, the RTL is proven equal to it
// (fpga/tests/test_rtl_blitter.py). docs/BLITTER_HW_SPEC.md §4.5-4.7.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Console = zg.Console;
const assets = @import("chisel_v2/assets.zig");
const modes = @import("chisel_v2/modes.zig");
const play = @import("chisel_v2/play.zig");
const parrot = @import("../assets/screens/parrot/parrot.zig");

const NAMES = [5][]const u8{ "ROTOZOOM", "MODE 7", "TUNNEL", "SPRITES", "FILL" };
const MODE_FRAMES: u32 = 300;
const K_ESC: u32 = 0xE012; // demo_main.zig's code for Escape
const TEXT_COL: u8 = 1;

pub const Demo = struct {
    a: assets.Assets = .{},
    m: modes.Modes = .{},
    p: play.Play = .{},
    mode: u8 = 0,
    auto: bool = true,
    hit: bool = false, // SPRITES: the collision bit after this frame's bobs
    ok: bool = false,
    wants_quit: bool = false,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("chisel_v2 init", .{});
        self.p = .{}; // the cart is zeroed, not default-initialised: the play defaults go in here
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
        parrot.install(fb); // 56..247, beside every index above: no palette swap on P
    }

    pub fn setShadeMode(self: *Demo, m: u32) void {
        self.mode = @intCast(@min(m, NAMES.len - 1));
        self.auto = false;
        Console.log("chisel_v2 mode -> {s}", .{NAMES[self.mode]});
    }

    // Declaring key() gives this cart every key (demo_main.zig): Escape and the play
    // keys are handled here, 1-5 still arrive through setShadeMode.
    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC) self.wants_quit = true;
        if (self.p.key(self.mode, cp)) self.auto = false; // playing stops the cycle
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        if (self.p.frozen) return;
        self.m.t +%= 1;
        self.p.step();
        if (self.auto and self.m.t % MODE_FRAMES == 0) self.mode = @intCast((self.mode + 1) % NAMES.len);
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb: *LogicalFB = &zigos.lfbs[0];
        if (!self.ok) return zigos.printText(fb, "NO RAM", 10, 8, TEXT_COL, 0);
        const tx = self.texture();
        switch (self.mode) {
            0 => self.m.rotozoom(fb, tx, &self.p.roto),
            1 => self.m.mode7(fb, tx, &self.p.floor),
            2 => self.m.tunnel(fb, tx, &self.a, &self.p.tube),
            3 => self.hit = self.m.sprites(fb, &self.a),
            else => self.m.star(fb),
        }
        self.label(zigos, fb, tx.log);
        if (self.mode == 3) zigos.printText(fb, if (self.hit) "HIT" else "---", 10, zg.HEIGHT - 16, TEXT_COL, 0);
    }

    /// The generated 128 texture, or the photo at the size T chose.
    fn texture(self: *const Demo) modes.Tex {
        if (!self.p.photo) return .{ .t = .{ .pixels = self.a.tex, .stride = assets.TEX, .umask = assets.TEX - 1, .vmask = assets.TEX - 1 }, .log = 7 };
        const n: u16 = @as(u16, 1) << self.p.log;
        return .{ .t = .{ .pixels = parrot.texture(self.p.log), .stride = n, .umask = n - 1, .vmask = n - 1 }, .log = self.p.log };
    }

    /// Two lines over the picture (rows 8..23): the mode, its texture, PAUSED; then its keys.
    fn label(self: *const Demo, zigos: *ZigOS, fb: *LogicalFB, log: u4) void {
        var buf: [40]u8 = undefined;
        const tex = if (self.mode > 2) "" else if (!self.p.photo) " GEN 128" else switch (log) {
            6 => " PHOTO 64",
            7 => " PHOTO 128",
            else => " PHOTO 256",
        };
        const pause = if (self.p.frozen) " PAUSED" else "";
        const line = std.fmt.bufPrint(&buf, "{s}{s}{s}", .{ NAMES[self.mode], tex, pause }) catch NAMES[self.mode];
        zigos.printText(fb, line, 10, 8, TEXT_COL, 0);
        zigos.printText(fb, play.help(self.mode), 10, 16, TEXT_COL, 0);
    }
};
