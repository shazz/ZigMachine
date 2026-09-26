// whichpart 5 -- the OMEGA SCREEN (screen.js do_omega), back to front:
//   omain.png (the frame) at (40,40); omega.png at (295,345);
//   the scroller: omegafont 30.7x28 cells (fractional: the positions and the
//     source rectangles are f64 throughout), speed 6, at y 300, masked by black
//     quads at x < 43 and x >= 576;
//   six LED VU meters (vumeter.png tiles, 198x11, tile 2*hvoice), each voice
//     mirrored at 293 and plain at 324, rows 341/353/365;
//   atari.png's 31 spinning frames (172x134, one per 2 frames) bouncing on
//     184 - |sin(logosiny) * 47|.
const frame = @import("frame.zig");
const gen = @import("assets_gen.zig");
const image = @import("image.zig");
const texts = @import("texts.zig");
const sc = @import("scroller.zig");
const Vu = @import("vu.zig").Vu;

const ifloor = image.ifloor;
const NONE = image.NONE;
const OFONT_W: f64 = 30.7;

pub const Omega = struct {
    frame_no: f64, // `frame`
    logosiny: f64,
    scroll: sc.Scroller,

    pub fn init(self: *Omega) void {
        self.frame_no = 0;
        self.logosiny = 0;
        self.scroll.init(texts.omega, OFONT_W, 640, 6, null);
    }

    pub fn step(self: *Omega, vu: *Vu, regs: *const [16]u8) void {
        vu.watch(regs);
        blit(&gen.omain, 20, 20, 128); // 640-space (40,40): even rows and columns
        omegaSign();
        self.scroll.advance();
        self.drawScroll();
        masks();
        for (0..3) |c| meters(vu.h[c], 341 + 12 * @as(i32, @intCast(c)));
        vu.remember(regs);
        self.logosiny += 0.06;
        self.atari();
        self.frame_no += 0.5;
        if (self.frame_no >= 31) self.frame_no = 0;
    }

    fn drawScroll(self: *Omega) void {
        var ord: [sc.MAX]u8 = undefined;
        const cells: f64 = 307.0 / OFONT_W; // img.width / tilew
        for (self.scroll.order(&ord)) |k| {
            const nb: f64 = @floatFromInt(@as(i32, self.scroll.ltr[k]) - 32);
            const partx = @floor(@mod(nb, cells)) * OFONT_W;
            const party = @floor(nb / cells) * 28;
            const partw = @min(OFONT_W, 307 - partx);
            const parth = @min(28, 168 - party);
            if (partw <= 0 or parth <= 0) continue;
            const posx = self.scroll.posx[k];
            var y: i32 = 150;
            while (y < 164) : (y += 1) {
                const r: f64 = @floatFromInt(2 * y - 300);
                if (r >= parth) continue;
                var x: i32 = @max(22, ifloor(posx / 2));
                while (x < 288) : (x += 1) {
                    const local = @as(f64, @floatFromInt(2 * x)) + 0.5 - posx;
                    if (local < 0) continue;
                    if (local >= partw) break;
                    const g = gen.ofont.at(ifloor(partx + local), ifloor(party + r));
                    if (g != NONE) frame.put(x, y, g);
                }
            }
        }
    }

    /// atari.drawTile(mycanvas, frame, 315, 184-|sin(logosiny)*47|), midhandled:
    /// top-left (229, y-67); column x-229 is odd for even x (the asset's columns).
    fn atari(self: *Omega) void {
        const nb = self.frame_no;
        const partx: i32 = @intFromFloat(@floor(@mod(nb, 4)) * 172);
        const party: i32 = @intFromFloat(@floor(nb / 4) * 134);
        const top = 184 - @abs(@sin(self.logosiny) * 47) - 67;
        var y: i32 = 0;
        while (y < 225) : (y += 1) {
            const r = ifloor(@as(f64, @floatFromInt(2 * y)) + 0.5 - top);
            if (r < 0 or r >= 134) continue;
            var x: i32 = 115;
            while (x < 201) : (x += 1) {
                const g = gen.atari.at(@divFloor(partx + 2 * x - 229, 2), party + r);
                if (g != NONE) frame.put(x, y, g);
            }
        }
    }
};

fn blit(img: *const image.Img, x0: i32, y0: i32, h: i32) void {
    var y: i32 = 0;
    while (y < h) : (y += 1) {
        var x: i32 = 0;
        while (x < img.w) : (x += 1) {
            const g = img.at(x, y);
            if (g != NONE) frame.put(x0 + x, y0 + y, g);
        }
    }
}

/// omega.draw(mycanvas, 295, 345): 640 columns 2X-295, rows 2Y-345.
fn omegaSign() void {
    var y: i32 = 173;
    while (y < 187) : (y += 1) {
        var x: i32 = 148;
        while (x < 162) : (x += 1) {
            const g = gen.omega.at(2 * x - 295, 2 * y - 345);
            if (g != NONE) frame.put(x, y, g);
        }
    }
}

/// The black quads (-7,300,50,50) and (576,300,80,50) are drawn before the
/// meters: ST x < 22 and x >= 288 on rows 150..174 go back to colour 0.
fn masks() void {
    var y: i32 = 150;
    while (y < 175) : (y += 1) {
        var x: i32 = 0;
        while (x < 320) : (x += 1) if (x < 22 or x >= 288) frame.put(x, y, 0);
    }
}

/// vumeter.drawTile(tile = (h/7)*14) mirrored at 293 (col 292-2X) and at 324.
fn meters(h: i32, row0: i32) void {
    const t: i32 = @intFromFloat(@floor(@as(f64, @floatFromInt(h)) / 7 * 14));
    var y: i32 = @divFloor(row0 + 1, 2);
    while (2 * y - row0 < 11) : (y += 1) {
        const r = t * 11 + 2 * y - row0;
        var x: i32 = 48;
        while (x < 261) : (x += 1) {
            const col = if (x <= 146) 292 - 2 * x else 2 * x - 324;
            if (col < 0 or col >= 198) continue;
            const g = gen.vumeter.at(@divFloor(col, 2), r);
            if (g != NONE) frame.put(x, y, g);
        }
    }
}
