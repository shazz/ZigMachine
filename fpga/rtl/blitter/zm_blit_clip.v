// The effective clip rectangle [x0,x1) x [y0,y1): the destination buffer (stride wide;
// 280 rows for a fullscreen stride, else 200, as machine/blitter.zig dstHeight), cut
// down by the CLIP rect when CON.CLIP_EN is set.
`default_nettype none
`include "memmap.vh"

module zm_blit_clip (
    input  wire [7:0]         con,
    input  wire [15:0]        ds,
    input  wire [15:0]        clip_x, clip_y, clip_w, clip_h,
    output wire signed [17:0] x0, y0, x1, y1
);
    wire signed [17:0] sds = {2'd0, ds};
    wire signed [17:0] dh = ds == ZM_STRIDE_FULLSCREEN ? ZM_PHYSICAL_HEIGHT : ZM_HEIGHT;
    wire signed [17:0] cx = {2'd0, clip_x}, cy = {2'd0, clip_y};
    wire signed [17:0] rx = cx + {2'd0, clip_w}, ry = cy + {2'd0, clip_h};  // <= 131070: fits
    wire en = con[7];
    assign x0 = en ? cx : 18'sd0;
    assign y0 = en ? cy : 18'sd0;
    assign x1 = en && rx < sds ? rx : sds;
    assign y1 = en && ry < dh ? ry : dh;
endmodule
