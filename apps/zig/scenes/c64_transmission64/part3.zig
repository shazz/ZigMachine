// --------------------------------------------------------------------------
// Part 3 ($3808): the dots and the info panel, forever (a 969-frame cycle, a new shape each).
//
// IRQ chain (lines and cycles from VICE's traces, prototypes/transmission64_re/vice/p3):
//   $3D30 (248)  the first four frames, while the main loop generates the shape's code
//   $3D79 (49)   screen on, charset 0, CIA 2's timer B: an NMI every 64 lines INCs $D018
//                (bit 0 reads as 1: +2, the next charset) at lines 114, 178, 242
//   $40AA (248)  invalid mode (black), charset 0, the VIC bank of the buffer drawn last frame
//                (L417F: bank 0 or 3), the music, the sprites, then the dots' work
//   $3DC1 / $4016 (248, writing at the next frame's line 0) the border flashes, screen off
//   $3E52 / $3F3D (248) the panel rolled in, held, rolled out
// What a handler does after the window (drawing, the panel's rows, colour RAM) runs in
// post(), after the VIC model has drawn the frame: none of it lands before line 251.
// --------------------------------------------------------------------------
const vic = @import("vic.zig");
const data3 = @import("data3.zig");
const Dots = @import("part3_dots.zig").Dots;
const panel_mod = @import("part3_panel.zig");

pub const INIT = 3151; // $09CE releases the main loop: part 3's code and data are in RAM
pub const REGS = 3152; // its init reaches $3879 on line 234 (the shape generation first)
pub const FIRST_DOTS = 3156; // $3D30 hands over to $40AA, on line 242 this once

pub const Irq = enum { wait, dots, flash, panel_in, panel_out, back };

pub const Part3 = struct {
    irq: Irq = .wait, // the handler the next frame's raster IRQ runs
    cur: Irq = .wait, // this frame's
    dots: Dots,
    panel: panel_mod.Panel = .{},
    buf: u8 = 0, // L417F: the buffer drawn last
    zoom_in: u8 = 0x6E, // L414D
    zoom_out: u8 = 0x6E, // L416C
    to_flash: bool = false, // L40EB
    nmi: bool = false, // $3D79 set up for this frame
    regen: bool = false, // L386B: the main loop has a shape to generate

    pub fn init(d: data3.Part3) Part3 {
        var p = Part3{ .dots = Dots.init(d) };
        p.dots.zp[0x16] = 0;
        p.dots.zp[0x17] = 0;
        p.dots.zp[0x1A] = 0;
        p.dots.zp[0x1B] = 0;
        p.dots.zp[0x1C] = 0x80;
        p.dots.zp[0x1D] = 0;
        p.dots.zp[0x1E] = 0xFA;
        p.dots.zp[0x23] = 0xFF;
        for ([_]u8{ 0x1F, 0x20, 0x21, 0x22, 0x24 }) |a| p.dots.zp[a] = 0x38;
        for (0..35) |i| for ([_]usize{ 0x25, 0x48, 0x6B }) |a| {
            p.dots.zp[a + i] = 0;
        };
        p.dots.clearSprites();
        return p;
    }

    /// The register writes of frame `n`'s IRQs.
    pub fn pre(self: *Part3, n: u32, q: *vic.Queue) void {
        if (n == REGS) initRegs(q);
        self.cur = self.irq;
        switch (self.cur) {
            .wait => q.w(263, 21, 0x21, 0x00),
            .dots => self.preDots(n, q),
            .flash, .back => {
                const x = if (self.cur == .flash) self.panel.flash_x else self.panel.back_x;
                q.w(312, 19, vic.BANK, 0xC0); // after waiting for the next frame's line 0
                q.w(312, 25, 0x18, 0x34);
                q.w(312, 31, if (self.cur == .flash) 0x15 else 0x11, if (self.cur == .flash) 0x00 else 0x0B);
                q.w(312, 41, 0x20, panel_mod.FLASH[x]);
                q.w(312, 47, 0x21, 0x00);
            },
            .panel_in, .panel_out => {
                q.w(262, 4, vic.BANK, 0xC0);
                q.w(262, 10, 0x18, 0x34);
                q.w(262, 16, 0x11, 0x1B);
            },
        }
    }

    fn preDots(self: *Part3, n: u32, q: *vic.Queue) void {
        if (self.nmi) {
            q.w(49, 26, 0x18, 0x28);
            q.w(49, 32, 0x11, 0x1B);
            for ([_]u16{ 114, 178, 242 }, [_]u8{ 0x2A, 0x2C, 0x2E }) |l, v| q.w(l, 61, 0x18, v);
        }
        const line: u16 = if (n == FIRST_DOTS) 242 else 248;
        q.w(line, 41, 0x11, 0x7B);
        q.w(line, 47, 0x18, 0x28);
        q.w(line + 1, 2, vic.BANK, if (self.buf != 0) 0xC3 else 0xC0);
        q.w(262, 22, 0x11, 0x1B);
        if (self.to_flash) { // L40EB, raised by the last frame's dots: screen off, flash next
            q.w(262, 40, 0x11, 0x0B);
            self.irq = .flash;
        }
        // $39DA: the sprite list the last frame's plot left
        const z = &self.dots.zp;
        if (z[0xF8] == 0) {
            q.w(264, 10, 0x15, 0x00);
        } else {
            var i: u8 = 0;
            while (i < z[0xF8]) : (i += 1) q.w(263, 20 + i, i, z[0xE8 + @as(usize, i)]);
            q.w(264, 10, 0x15, z[0xF9]);
            q.w(264, 17, 0x10, z[0xFA]);
        }
        self.nmi = !self.to_flash;
        self.to_flash = false;
    }

    /// The rest of frame `n`'s IRQs, after the window: into `ram`/`col` directly.
    pub fn post(self: *Part3, n: u32, ram: *[65536]u8, col: *[1024]u8, d: data3.Part3) void {
        if (n == INIT) {
            @memcpy(ram[0x2000..0x4000], d.bank0());
            @memcpy(ram[0xC000..0x10000], d.bank3());
            self.mainInit(ram, col, d);
            return;
        }
        switch (self.cur) {
            .wait => if (n + 1 == FIRST_DOTS) {
                self.irq = .dots;
            },
            .dots => self.postDots(ram, d),
            .flash => self.postFlash(ram, col),
            .panel_in => if (self.panel.rollIn(ram, col)) {
                self.irq = .panel_out;
            },
            .panel_out => if (self.panel.rollOut(ram, col)) {
                self.irq = .back;
            },
            .back => self.postBack(ram, col, d),
        }
    }

    // $3808..$3866: the shape's code, colours, screens, sprite block, erase lists, tables.
    fn mainInit(self: *Part3, ram: *[65536]u8, col: *[1024]u8, d: data3.Part3) void {
        self.dots.generate(d);
        for (0..512) |i| col[i] = ram[0xDA00 + i] & 15; // $38B9
        for (0..512) |i| col[512 + i] = ram[0xDC00 + i] & 15; // $38D3
        @memcpy(ram[0x0800..0x0C00], ram[0xC800..0xCC00]);
        for (0..8) |i| {
            ram[0x0BF8 + i] = 0x1C;
            ram[0xCBF8 + i] = 0x1C;
        }
        @memcpy(ram[0x0700..0x073F], ram[0xC700..0xC73F]);
        for (0..256) |y| ram[0x0600 + y] = @intCast(y & 0xF8);
    }

    // $3879 and $3927 on line 234 (the shape generation took the frame before): invalid mode,
    // 40 columns, bank 0, the sprites cleared and white.
    fn initRegs(q: *vic.Queue) void {
        for ([_][2]u8{ .{ 0x11, 0x7B }, .{ 0x16, 0xC8 }, .{ 0x18, 0x18 }, .{ vic.BANK, 0xC7 } }, 0..) |w, k| q.w(234, @intCast(30 + 6 * k), w[0], w[1]);
        var c: u8 = 0;
        for ([_]u8{ 0x10, 0x15, 0x17, 0x1B, 0x1C, 0x1D }) |r| {
            q.w(235, c, r, 0);
            c += 4;
        }
        for (0..16) |r| q.w(236, @intCast(3 * r), @intCast(r), 0);
        for (0..8) |r| q.w(237, @intCast(6 * r), @intCast(0x27 + r), 1);
    }

    fn postDots(self: *Part3, ram: *[65536]u8, d: data3.Part3) void {
        // the main loop generates the next shape's code between this IRQ and the last one,
        // and has not reached the depth axis when this one runs it: x and y are the new
        // shape's, the depth still the old one's (VICE's later frames say so)
        const z_old = self.regen;
        if (self.regen) {
            self.regen = false;
            self.dots.generate(d);
        }
        const z = &self.dots.zp;
        if (z[0x23] == 0) { // hold
            z[0x1E] -%= 1;
            if (z[0x1E] == 0) {
                z[0x1E] = 0xFA;
                z[0x24] = 0;
                for ([_]u8{ 0x1F, 0x20, 0x21, 0x22 }) |a| z[a] = 0x22;
                z[0x23] = 1;
            }
        } else if (z[0x23] < 0x80) { // in: one more dot every other frame, 111 frames
            if (self.buf == 0) z[0x24] +%= 1;
            self.zoom_in -%= 1; // LDA #n / BPL: on until it passes 0
            if (self.zoom_in >= 0x80) {
                self.zoom_in = 0x6E;
                self.regen = true; // the main loop, released ($386B), generates the next shape
                z[0x23] = 0xFF;
                self.to_flash = true;
            }
        } else { // out
            if (self.buf == 0) z[0x24] -%= 1;
            self.zoom_out -%= 1;
            if (self.zoom_out >= 0x80) {
                self.zoom_out = 0x6E;
                z[0x23] = 0;
            }
        }
        self.dots.clearSprites();
        self.buf ^= 0xFF;
        const b: usize = if (self.buf != 0) 0 else 1;
        self.dots.erase(b, z[0x21 + b], ram, d);
        if (z[0x23] != 0) {
            const c = d.bank3()[0x0780 + @as(usize, z[0x24])];
            z[0x21 + b] = c;
            z[0x1F + b] = c;
        }
        self.dots.coords(d, z_old);
        self.dots.plot(b, z[0x1F + b], ram, d);
    }

    fn postFlash(self: *Part3, ram: *[65536]u8, col: *[1024]u8) void {
        self.panel.flash_x += 1;
        if (self.panel.flash_x == 12) {
            self.panel.flash_x = 0;
            self.irq = .panel_in;
            return;
        }
        @memset(col, 4);
        self.panel.anim(ram);
    }

    fn postBack(self: *Part3, ram: *[65536]u8, col: *[1024]u8, d: data3.Part3) void {
        _ = d;
        self.panel.back_x += 1;
        if (self.panel.back_x == 0x0F) {
            self.panel.back_state += 1;
            self.panel.back_x = 4;
        }
        self.panel.anim(ram);
        switch (self.panel.back_state) {
            1 => {
                for (0..512) |i| col[i] = ram[0xDA00 + i] & 15;
                self.panel.back_state = 2;
            },
            2 => {
                for (0..512) |i| col[512 + i] = ram[0xDC00 + i] & 15;
                self.panel.back_state = 3;
            },
            4 => {
                self.panel.back_state = 1;
                self.irq = .dots;
            },
            else => {},
        }
    }
};
