// --------------------------------------------------------------------------
// The fullscreen geometry, shared by the cart and the native test.
//
// The plane is an OVERSCAN SCROLL plane: a BUF_W x BUF_H buffer of which the
// hardware shows a 400x280 window (every border open once the show has opened
// them), panned by setScroll(). The background is back.raw TILED over the
// buffer, and placed so that on the first frame the 320x200 middle of the
// window shows the picture exactly as the leonard cart does. The balls stay
// put on the screen: they are drawn at window position + scroll.
// --------------------------------------------------------------------------
pub const WIN_W = 400; // the overscan window (physical 400x280)
pub const WIN_H = 280;
pub const BX = 40; // side border width / top border height in the window
pub const BY = 40;
pub const TILE_W = 320; // back.raw
pub const TILE_H = 200;
pub const PAN_X = 176; // the scroll's range: 0..PAN_X, 0..PAN_Y
pub const PAN_Y = 168;
pub const BUF_W = WIN_W + PAN_X; // 576
pub const BUF_H = WIN_H + PAN_Y; // 448
pub const SCROLL_Y = BY + 194; // the scrolltext: the leonard cart's row 194

/// Buffer pixel (x, y) shows back.raw pixel (tileX(x), tileY(y)); ox, oy put
/// tile (0,0) at the window's (BX, BY) on the first frame (scroll (ox-BX, oy-BY)).
pub fn tileX(x: u32, ox: u32) u32 {
    return (x + TILE_W * 2 - ox) % TILE_W;
}
pub fn tileY(y: u32, oy: u32) u32 {
    return (y + TILE_H * 3 - oy) % TILE_H;
}

comptime {
    if (BUF_W % 4 != 0) @compileError("the generated ball stores need a u32 row stride");
}
