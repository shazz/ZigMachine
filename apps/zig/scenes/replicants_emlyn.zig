// --------------------------------------------------------------------------
// THE REPLICANTS — "Emlyn Hughes International Soccer" crack intro.
// Coding -VICKERS-, Amiga font ripped by -VANTAGE- of ST CONNEXION, the big
// REPLICANTS logo by -PULSAR- of NEXT, music by -MAD MAX- of TEX; the
// scrolltext is theirs word for word.
//
// Ported from the CODEF HTML5 remake (wab.com screen 17, MIT), kept at
// prototypes/codef/17/. Assets: tools/private_tools/replicants_emlyn_assets.py.
// init() goes straight to go(): there is no depacker intro to skip.
//
// The remake canvas is 640x480 = ST 320x240 doubled, and go() fills all of it,
// so this ST screen ran with a border open. The 320x240 content sits at (40,20)
// in the 400x280 overscan plane, borders opened with the res-flicker trick.
//
// go() (screen.js:94-115), in its own order, once a frame:
//   canvas.fill('#000000')
//   group.rotation.x += 0.04, then my3d.draw()      12 bars (emlyn/balls.zig)
//   logo.draw(320 + posx, 300 + sin(posy)*300)      mid-handled, 2190x314 ST
//   scrolltext.draw(390)                            flat, speed 4
//   then posx steps +-32 between +-1920 and posy += 0.02
// Note the logo moves AFTER it is drawn while the rotation moves before, so the
// first frame shows rotation 0.04 at logo position (0, 0). update() keeps that.
//
// TWO DELIBERATE DIVERGENCES FROM THE REMAKE (Matt, and the point of them is
// that the remake is the deficient artefact here):
//
//  1. The bars are REAL RASTERS, borders included. The remake blits bar.png as
//     a sprite; the ST screen changed the palette per scanline, which is what
//     bar.png's 64 one-colour rows were always a table FOR. So the background is
//     a ramp of palette indices across all 400 raster columns and the plane's
//     HBL colours them per line (emlyn/rasters.zig). Nothing of the bars is in
//     the framebuffer, and every border is open so they run edge to edge. The
//     LOGO and the SCROLLTEXT are drawn to the whole 400x280 raster for the
//     same reason: on a fullscreen screen there is no edge to stop at.
//  2. SPACE switches between ORIGINAL (the faithful screen 17) and ZIG, where
//     the bars turn through every direction AND the scrolltext bends on CODEF
//     484's middle-scroller curve (emlyn/scroller.zig), the one picked out of
//     the distortion lab. Both grow in and flatten out over the same 20 frames.
//
// ONE plane, one palette: 107 entries of art (unquantized) + up to 149 raster
// buckets. Per frame: a colour table, the 400-byte ramp pattern put back where
// last frame drew over it (all of it only when the bucket count changes:
// emlyn/dirty.zig), one clipped logo blit and 14 glyphs.
//
// NUMBERS. The remake computes in JavaScript doubles, and so did this port
// until the board's cart CPU (rv32im, no FPU) measured it at 9 Mc a frame in
// ORIGINAL mode — 550 MHz for 60 fps, two thirds of it soft-float. This cart
// now runs the screen the way the ST coder would have: a sine table, Q16.16
// and one span per bar per line (emlyn/fixed.zig). The CODEF algorithm itself
// is kept in f32 (emlyn/float.zig), to measure a single-precision FPU against:
// F switches this cart's per-frame maths to it and back, live (emlyn/app.zig),
// so one cart shows both speeds on the board's frame counter. The twin cart
// replicants_emlyn_f32 is the same Demo booting on the f32 side.
// --------------------------------------------------------------------------
pub const Demo = @import("replicants_emlyn/app.zig").Demo(false);
