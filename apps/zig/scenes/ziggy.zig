// --------------------------------------------------------------------------
// ZIGGY: the cart CPU's showcase. Two loops that used to choke an rv32 at
// 100 MHz, drawn by the CPU alone, every pixel of the picture a frame:
//   1   ROTO    a rotozoom; T cycles the texture 64 / 128 / 256 (4 / 16 /
//               64 KB: what ZIGGY's 16 KB D-cache holds, and what it doesn't)
//   P           ROTO: the texture, generated (GEN) or a real photo (PHOTO, a scarlet
//               macaw, public domain: assets/screens/parrot/) at the same three sizes and
//               the same cost; its own 192-colour palette while it is shown
//   2   VOXEL   a Comanche-style landscape over a 256x256 height map
//   Z           ZM-X on / off: the custom ops (tex2d, mulsh16: one instruction
//               each on the board) or the plain rv32 code they replace. The
//               two give the SAME pixels (the harness checks it), only the
//               cost moves
//   + / -       ROTO: the rotation speed, -8 .. +8 steps (4 = the default turn every ~17 s,
//               0 = still, negative = the other way)
//   F           freeze the camera (the same frame again and again: toggle Z or T on it
//               and the Mc line is a clean A/B)
//   Esc         back to the menu
// Under the picture: FPS, the cart's own time a frame in Mc at 100 MHz, and
// cycles a pixel (fpga/review/KESTREL_NEXT_ISA.md's roto128 and voxel256
// loops, now on the hardware they asked for). The CHISEL V2 cart does the
// rotozoom with the blitter instead; this one is the CPU's.
// Everything is generated at init (ziggy/maps.zig), but the photo, converted at
// build time (tools/parrot_tex.py); integers per frame.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const maps = @import("ziggy/maps.zig");
const roto = @import("ziggy/roto.zig");
const voxel = @import("ziggy/voxel.zig");
const parrot = @import("../assets/screens/parrot/parrot.zig");
const Hud = @import("ziggy/hud.zig").Hud;

const K_ESC: u32 = 0xE012;
const LOGS = [_]u4{ 6, 7, 8 };
pub const Mode = enum(u8) { roto, voxel };

pub const Demo = struct {
    os: *zg.ZigOS = undefined,
    tex: []u8 = &.{},
    heights: []u8 = &.{},
    colours: []u8 = &.{},
    depth: *voxel.Depth = undefined,
    map: []u16 = &.{},
    hud: Hud = .{},
    mode: Mode = .roto,
    size: u8 = 1, // index in LOGS: 128 by default
    zmx_on: bool = true,
    photo: bool = false, // ROTO's texture: the photo instead of the generated one
    t: u32 = 0,
    cam_h: i32 = 0,
    frozen: bool = false,
    spin: i8 = 4, // ROTO's rotation speed, in steps of a quarter of the default turn
    angle: u32 = 0, // ROTO's rotation, turned by `spin` a frame
    wants_quit: bool = false,

    pub fn init(self: *Demo, zigos: *zg.ZigOS) void {
        zg.Console.log("ziggy init", .{});
        self.* = .{}; // the cart is zeroed, not default-initialised
        self.os = zigos;
        self.tex = zg.mem.mustAlloc(u8, maps.TEX_BYTES);
        self.heights = zg.mem.mustAlloc(u8, 256 * 256);
        self.colours = zg.mem.mustAlloc(u8, 256 * 256);
        self.depth = &zg.mem.mustAlloc(voxel.Depth, 1)[0];
        self.map = zg.mem.mustAlloc(u16, 256 * 256);
        maps.buildTextures(self.tex);
        maps.buildHeights(self.heights);
        maps.buildColours(self.heights, self.colours);
        voxel.merge(self.heights, self.colours, self.map);
        self.depth.init();
        const fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        zigos.setBackgroundColor(.{ .r = 0, .g = 0, .b = 0, .a = 255 });
        self.select(.roto);
    }

    fn select(self: *Demo, m: Mode) void {
        self.mode = m;
        const fb = &self.os.lfbs[0];
        switch (m) {
            .roto => if (self.photo) photoPalette(fb) else maps.rotoPalette(fb),
            .voxel => maps.voxelPalette(fb),
        }
        self.hud.reset();
        self.hud.invalidate();
        // The HUD rows' paper: the picture never reaches them.
        @memset(fb.fb[@as(usize, roto.ROWS) * fb.stride .. @as(usize, 200) * fb.stride], maps.PAPER);
    }

    pub fn ownsKeyboard(self: *Demo) u32 {
        _ = self;
        return 1;
    }

    pub fn key(self: *Demo, cp: u32) void {
        switch (cp) {
            K_ESC => self.wants_quit = true,
            '1' => self.select(.roto),
            '2' => self.select(.voxel),
            't', 'T' => {
                self.size = @intCast((self.size + 1) % LOGS.len);
                self.hud.reset();
            },
            'z', 'Z' => {
                self.zmx_on = !self.zmx_on;
                self.hud.reset();
            },
            'p', 'P' => self.setPhoto(!self.photo),
            'f', 'F' => self.frozen = !self.frozen,
            '+', '=' => self.spin = @min(self.spin + 1, 8),
            '-', '_' => self.spin = @max(self.spin - 1, -8),
            else => {},
        }
    }

    /// ROTO's texture: the photo or the generated one (its palette goes in at once in ROTO).
    fn setPhoto(self: *Demo, on: bool) void {
        self.photo = on;
        if (self.mode == .roto) self.select(.roto);
    }

    /// The host's digit switch (loader, glass, harnesses): 0 ROTO, 1 VOXEL,
    /// 2 ZM-X off, 3 ZM-X on, 4..6 texture 64 / 128 / 256, 7 generated texture, 8 photo.
    pub fn setShadeMode(self: *Demo, m: u32) void {
        switch (m) {
            0 => self.select(.roto),
            1 => self.select(.voxel),
            2, 3 => self.zmx_on = m == 3,
            4...6 => self.size = @intCast(m - 4),
            7, 8 => self.setPhoto(m == 8),
            else => {},
        }
        self.hud.reset();
    }

    pub fn update(self: *Demo, zigos: *zg.ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        if (self.frozen) return;
        self.t +%= 1;
        self.angle +%= @bitCast(@as(i32, self.spin) * 1_050_000);
    }

    pub fn render(self: *Demo, zigos: *zg.ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[0];
        self.hud.workStart();
        switch (self.mode) {
            .roto => {
                const all: []const u8 = if (self.photo) parrot.all else self.tex;
                roto.draw(fb, maps.texture(all, LOGS[self.size]), LOGS[self.size], self.zmx_on, self.t, self.angle);
            },
            .voxel => {
                const cam = voxel.camera(self.t, self.heights, self.cam_h);
                self.cam_h = cam.h;
                voxel.draw(fb, self.depth, self.map, cam, self.zmx_on);
            },
        }
        self.hud.workEnd();
        const size: u32 = if (self.mode == .roto) @as(u32, 1) << LOGS[self.size] else 0;
        const name = if (self.mode == .voxel) "     " else if (self.photo) "PHOTO" else "GEN  ";
        self.hud.draw(zigos, fb, if (self.mode == .roto) "ROTO " else "VOXEL", .{ .size = size, .name = name }, self.zmx_on);
    }
};

/// ROTO's palette while the photo is shown: its 192 colours at 56..247 and the HUD's
/// 254/255 (the photo's indices never reach 248..253, nor 0..55).
fn photoPalette(fb: *zg.LogicalFB) void {
    parrot.install(fb);
    maps.hud(fb);
}
