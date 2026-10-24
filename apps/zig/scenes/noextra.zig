// --------------------------------------------------------------------------
// NOEXTRA — "RASTERS", Zorro 2 / NoExtra Team's intro for the D.H.S. ST
// Demoscreen Competition 2005 (DHS Online Compo 2005). Code Zorro 2, music
// "Mega 4 Disk Mag" by Powa Pixel, graphics by Mister.A of NoExtra; the
// scrolltext is theirs word for word.
//
// PORTED FROM THE ORIGINAL BINARY (fujiology.org ST/N/NOEXTRA/RASTERS.ZIP),
// not from a remake. This screen was first ported (#127) from Mellowman's
// CODEF remake (wab.com screen 198), which got most of it wrong: logos scaled
// down to ~65% and re-sampled (the blur), a 640-px rainbow PICTURE line-shifted
// by two sines where the ST changes colour 0 every 12 pixels of every line, a
// 32x17 font, an ']'-triggered bob at +-40 where the ST bounces 0..59 lines on
// a table after 767 frames, a remixed scrolltext, a fade-in the intro never
// had, and a YM dump of a different tune. Everything below comes out of the
// depacked RASTERS.PRG (noextra/assets.zig lists every offset).
//
// What the screen does:
//   * intro — the D.H.S logo on a plain screen, held 254 frames, bounced on
//     the bob table for 255, held 239, then cut to black;
//   * main — NOEXTRA (320x69) above, ZORRO 2 (320x100) below, between them a
//     146-line band of colour-0 rasters (37 writes a line, two summed sine
//     tables per line) framed by two one-line gradient bars, and a one-plane
//     32x16 scroller at 8 px a frame whose 16-px columns ride a wave table;
//   * after 767 frames the whole screen bobs (a 74-frame table) for good.
// All borders are open (the top logo starts on the top border's lines, ZORRO 2
// runs into the bottom one, and the rasters run edge to edge).
//
// The cart: one 400x340 overscan plane panned by the bob, one HBL that opens
// the borders and replays the band's colours, the logos and bands drawn once,
// 20 scroller columns written per frame. No maths per frame beyond table
// lookups and adds, as in the original. noextra/app.zig is the cart.
// --------------------------------------------------------------------------
pub const Demo = @import("noextra/app.zig").Demo;
