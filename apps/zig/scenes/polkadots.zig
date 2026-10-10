// --------------------------------------------------------------------------
// POLKA DOTS — the halftone torus of CODEF screen 81 (wab.com), by Antoine
// Santo / NoNameNo, MIT. Reference kept at prototypes/codef/81/.
//
// SCOPE. The torus and nothing else, by request. The original screen also
// carries a logo, a starfield, a tweened block of letters, a bouncing bubble,
// two scrolling raster strips (screen.js:113-155) and 4MAT's ProTracker module
// "carvup-2" (screen.js:30); none of that is here. The torus gets the plain
// black field the original fills first (screen.js:105), and the screen is
// silent. There is no depacker intro on this screen to skip.
//
// WHAT IT DOES. A flat-shaded torus is rendered into a TINY offscreen canvas,
// then each of that canvas's pixels is read back and stamped onto the real
// screen as one of TEN 7x7 dots, chosen by the pixel's red value. Dot size is
// the intensity. screen.js:126-132:
//
//     var imgPixels = mycanvaspetit.contex.getImageData(0, 0, 71, 48);
//     for (y...48) for (x...71) {
//         var shit = Math.floor(imgPixels.data[i] * 0.0392156862745);
//         if (imgPixels.data[i] != 0) pat.drawTile(mycanvas, shit, x*7+71, y*7+72+70);
//     }
//
// GEOMETRY — the 2x is NOT in the art. pat.png's dots have single-pixel
// features (tile 1 is one pixel, tile 2 a five-pixel plus), so the tiles are
// native 1x and halving them would destroy them. The 7 px cell pitch is
// therefore kept exactly, and it is the GRID that is resized to the machine's
// screen: 45 x 28 cells = 315 x 196, centred on 320x200. Because the
// projection's vertical field of view does not depend on the canvas size, the
// torus still fills the same fraction of the screen's HEIGHT as it does of the
// original's (75%, measured over a full revolution); only the horizontal
// margin follows the wider screen. No borders are needed and none are opened.
//
// ONE PLANE, 12 colours: the black field, the tiles' own (7,7,7) and the ten
// dot inks. The original draws everything onto one canvas; so does this.
//
// FOUR RENDER MODES, ONE GRID. Keys 1..4 (or Space) switch only the RENDERER;
// the CPU half — torus.zig projecting and shade.zig reducing — is identical for
// all of them, which is the split the example exists to teach. Every mode
// drives the real blitter, and the bottom line reports the operations it issued
// and the pixels it touched, because the cost is half of the comparison:
//
//   1 DOT SIZE   one BLIT per lit cell from a ten-dot sheet (dots.zig)
//   2 HALFTONE   one FILL per RUN, shaded by the HALFTONE register
//   3 SOLID      one FILL per run, shaded by the palette — the baseline
//   4 FILL DOTS  one FILL per lit cell, a square sized by the intensity
//
// Escape leaves. Declaring key() takes Escape away from the host, so this
// scene sets wants_quit itself.
//
// COST (apps/polkadots_headless.mjs, averaged over 40 interleaved rounds on the
// same torus): 223 / 99 / 123 / 173 blitter operations a frame, all four at
// ~0.3 ms in the cart. The halftone register covers the grid in less than half
// the operations of the dot sheet because a RUN of equal cells is one fill —
// and it cannot vary the dot. That trade is what the screen is for.
//
// NUMBERS. The remake computes in JavaScript doubles, and so did this port
// until the board's cart CPU (rv32im, no FPU) measured it at 36 Mc a frame:
// 2.2 GHz for 60 fps, 2 fps on the board. This cart now projects, lights and
// fills the torus in integers (polkadots/shade_fixed.zig, project_fixed.zig).
// The CODEF algorithm itself is kept, in f32, as the separate cart
// polkadots_f32 (polkadots/shade_f32.zig), to measure a single-precision FPU
// against. polkadots/app.zig is the one Demo both instantiate.
// --------------------------------------------------------------------------
pub const Demo = @import("polkadots/app.zig").Demo(@import("polkadots/shade_fixed.zig"));
