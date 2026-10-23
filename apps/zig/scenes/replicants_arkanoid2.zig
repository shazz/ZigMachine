// --------------------------------------------------------------------------
// THE REPLICANTS — "Arkanoid II (Revenge of Doh)" crack intro, Atari ST,
// 1988 (cracked 19.07.88 per its scrolltext). Code R.AL, graphics Hofa,
// music Mad Max.
//
// Ported from the CODEF HTML5 remake by NoNameNo (wab.com screen 33, MIT).
// Graphics, scrolltext and the original ST intro belong to The Replicants;
// music: Mad Max's "Pro BMX Simulator A" — the remake plays
// 'Pro BMX Simulator A.ym'; here its SNDH, the same file Garfield (cart 31)
// plays (docs/music/pro_bmx_simulator_a.sndh, FLAG ~y).
//
// Reference kept at prototypes/codef/33/ (tools/private_tools/fetch_codef.py 33).
// Assets: tools/private_tools/replicants_arkanoid2_assets.py.
//
// The remake is 640x400 = ST 320x200 doubled, and everything it draws lies
// inside it (curve x <= 608+30, the strip at 368..399): no border is opened.
// What go() draws each frame, back to front:
//
//   1. bg.png, the whole screen (the logo, the mace man, the green band).
//   2. The scrolltext strip at y 368, straight or waving (scroller.zig).
//   3. One crew name, letter by letter along mycurve (names.zig).
//
// There is no raster in this screen: bg's colours are ST-legal art, constant
// per pixel. One plane, one 16-colour palette. bg is painted once at init;
// each frame copies bg back under last frame's letters and under the strip
// only, then draws the strip and the letters.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const ZigOS = zg.ZigOS;

const art = @import("replicants_arkanoid2/art.zig");
const Scroller = @import("replicants_arkanoid2/scroller.zig").Scroller;
const Names = @import("replicants_arkanoid2/names.zig").Names;

const MUSIC = "pro_bmx_simulator_a.sndh";
const PLANE = 0;

pub const Demo = struct {
    scroller: Scroller,
    names: Names,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        // A cart's Demo arrives zeroed: every field is set here, never by default.
        self.scroller.init();
        self.names.init();

        zg.requestSong(MUSIC);

        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.setPalette(art.palette);
        blit.blit(blit.Dst.plane(fb), art.bg, null, 0, 0, null, .copy);
    }

    /// go()'s state changes, in its order; the values it draws with are kept.
    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        self.scroller.step();
        self.names.step();
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const plane = blit.Dst.plane(&zigos.lfbs[PLANE]);
        self.names.erase(plane);
        self.scroller.draw(plane);
        self.names.draw(plane);
    }
};
