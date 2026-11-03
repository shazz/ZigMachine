// --------------------------------------------------------------------------
// ZIGGY: the cart CPU's showcase. Two loops that used to choke an rv32 at
// 100 MHz, drawn by the CPU alone, every pixel of the picture a frame:
//   1   ROTO    a rotozoom; T cycles the texture 64 / 128 / 256 (4 / 16 /
//               64 KB: what ZIGGY's 16 KB D-cache holds, and what it doesn't)
//   2   VOXEL   a Comanche-style landscape over a 256x256 height map
//   Z           ZM-X on / off: the custom ops (tex2d, mulsh16: one instruction
//               each on the board) or the plain rv32 code they replace. The
//               two give the SAME pixels (the harness checks it), only the
//               cost moves
//   F           freeze the camera (the same frame again and again: toggle Z or T on it
//               and the Mc line is a clean A/B)
//   Esc         back to the menu
// Under the picture: FPS, the cart's own time a frame in Mc at 100 MHz, and
// cycles a pixel (fpga/review/KESTREL_NEXT_ISA.md's roto128 and voxel256
// loops, now on the hardware they asked for). The CHISEL V2 cart does the
// rotozoom with the blitter instead; this one is the CPU's.
// Everything is generated at init (ziggy/maps.zig); integers per frame.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const maps = @import("ziggy/maps.zig");
const roto = @import("ziggy/roto.zig");
const voxel = @import("ziggy/voxel.zig");
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
    hud: Hud = .{},
    mode: Mode = .roto,
    size: u8 = 1, // index in LOGS: 128 by default
    zmx_on: bool = true,
    t: u32 = 0,
    cam_h: i32 = 0,
    frozen: bool = false,
    wants_quit: bool = false,

    pub fn init(self: *Demo, zigos: *zg.ZigOS) void {
        zg.Console.log("ziggy init", .{});
        self.* = .{}; // the cart is zeroed, not default-initialised
        self.os = zigos;
        self.tex = zg.mem.mustAlloc(u8, maps.TEX_BYTES);
        self.heights = zg.mem.mustAlloc(u8, 256 * 256);
        self.colours = zg.mem.mustAlloc(u8, 256 * 256);
        self.depth = &zg.mem.mustAlloc(voxel.Depth, 1)[0];
        maps.buildTextures(self.tex);
        maps.buildHeights(self.heights);
        maps.buildColours(self.heights, self.colours);
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
            .roto => maps.rotoPalette(fb),
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
            'f', 'F' => self.frozen = !self.frozen,
            else => {},
        }
    }

    /// The host's digit switch (loader, glass, harnesses): 0 ROTO, 1 VOXEL,
    /// 2 ZM-X off, 3 ZM-X on, 4..6 texture 64 / 128 / 256.
    pub fn setShadeMode(self: *Demo, m: u32) void {
        switch (m) {
            0 => self.select(.roto),
            1 => self.select(.voxel),
            2, 3 => self.zmx_on = m == 3,
            4...6 => self.size = @intCast(m - 4),
            else => {},
        }
        self.hud.reset();
    }

    pub fn update(self: *Demo, zigos: *zg.ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        if (!self.frozen) self.t +%= 1;
    }

    pub fn render(self: *Demo, zigos: *zg.ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[0];
        self.hud.workStart();
        switch (self.mode) {
            .roto => roto.draw(fb, maps.texture(self.tex, LOGS[self.size]), LOGS[self.size], self.zmx_on, self.t),
            .voxel => {
                const cam = voxel.camera(self.t, self.heights, self.cam_h);
                self.cam_h = cam.h;
                voxel.draw(fb, self.depth, self.heights, self.colours, cam, self.zmx_on);
            },
        }
        self.hud.workEnd();
        const size: u32 = if (self.mode == .roto) @as(u32, 1) << LOGS[self.size] else 0;
        self.hud.draw(zigos, fb, if (self.mode == .roto) "ROTO " else "VOXEL", size, self.zmx_on);
    }
};
