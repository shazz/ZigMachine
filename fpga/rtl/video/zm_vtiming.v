// ZigMachine video timing: VESA 800x600 @ 60 Hz (40 MHz pixel clock) carrying
// the machine's 800x280 raster (memmap RASTER_WIDTH x RASTER_HEIGHT) with every
// raster line shown twice, centred vertically (20 blank output lines above and
// below). Horizontally the raster is already 800 wide (low res is pixel-doubled
// into it), so x maps 1:1.
//
// The HBL strobe `zm_hbl` fires once per RASTER line, at the start of the
// horizontal blank BEFORE that line's first output line, with `zm_hbl_line`
// naming the line about to be drawn. A handler or a copper list therefore has
// the whole blank (256 clocks: 40 + 128 + 88) before pixel 0.
// `zm_vbl` fires once a frame, at pixel 0 of output line 580 (the first after the
// raster).
//
// Desk mode (`desk`, RES_DESK, HW 1.17.0, docs/GEM_DESK_MODE.md): the raster is
// 640x480, every line shown ONCE, in the middle of the output (80-pixel sides,
// 60-line bars), so zm_x counts from output pixel 80 and an HBL announces every
// line. The VESA timing never changes (the sink never resyncs), and neither does
// the VBL: line 580 is past both rasters' last line and before both first ones,
// so the mode, sampled there (`desk_q`, which the scanout fetch reads), switches only
// between whole frames. The geometry takes it at line 0 (`desk_g`): lines 540..579 are
// not desk lines but would be normal ones.
`default_nettype none

module zm_vtiming (
    input  wire        clk,            // pixel clock, 40 MHz
    input  wire        rst,
    input  wire        desk,           // RES_DESK, synchronised: takes effect at the next VBL
    output reg         desk_q = 1'b0,  // the mode of the next frame, from its VBL on
    output reg         desk_g = 1'b0,  // the mode of this frame's geometry, from line 0 on
    output reg         hsync,          // positive polarity (VESA 800x600@60)
    output reg         vsync,          // positive polarity
    output reg         de,             // output-frame display enable (800x600)
    output reg  [10:0] out_x,          // 0..1055
    output reg  [9:0]  out_y,          // 0..627
    output reg         zm_active,      // inside the 800x280 raster (doubled), or the desk's 640x480
    output reg  [9:0]  zm_x,           // raster x, 0..799 (desk 0..639) while zm_active
    output reg  [8:0]  zm_line,        // raster line, 0..279 (desk 0..479) while zm_active
    output reg         zm_hbl,         // one-clock HBL strobe per raster line
    output reg  [8:0]  zm_hbl_line,    // the raster line zm_hbl announces
    output reg         zm_vbl          // one-clock strobe per frame
);
`undef ZM_MEMMAP_VH  // memmap.vh's include guard would hide it from all but the first module of a read
`include "memmap.vh"

    localparam integer H_ACTIVE = 800, H_FP = 40, H_SYNC = 128, H_BP = 88;
    localparam integer V_ACTIVE = 600, V_FP = 1, V_SYNC = 4, V_BP = 23;
    localparam integer H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;  // 1056
    localparam integer V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;  // 628
    localparam integer ZM_TOP = (V_ACTIVE - 2 * ZM_RASTER_HEIGHT) / 2;  // 20
    localparam integer ZM_BOTTOM = ZM_TOP + 2 * ZM_RASTER_HEIGHT;       // 580
    localparam integer D_TOP = (V_ACTIVE - ZM_DESK_HEIGHT) / 2;          // 60
    localparam integer D_LEFT = (H_ACTIVE - ZM_DESK_WIDTH) / 2;          // 80

    // The next pixel's position, registered below so every output is aligned.
    wire        h_wrap = (out_x == H_TOTAL - 1);
    wire [10:0] nx = h_wrap ? 11'd0 : out_x + 11'd1;
    wire [9:0]  ny = !h_wrap ? out_y : (out_y == V_TOTAL - 1) ? 10'd0 : out_y + 10'd1;
    // The raster line of out_y, counted (out_y - top, mod 1024: above the raster it is past the
    // last line), one adder for both modes: the frame starts it at -top, each line adds one.
    reg  [9:0]  ry = 10'd0;
    wire [9:0]  rows = desk_g ? ZM_DESK_HEIGHT[9:0] : 2 * ZM_RASTER_HEIGHT[9:0];  // output lines
    wire [9:0]  ry1 = ry + 10'd1;
    wire [9:0]  n_raster_y = !h_wrap ? ry : (ny == 0) ? 10'd0 - (desk_q ? D_TOP[9:0] : ZM_TOP[9:0]) : ry1;
    wire        frame_start = h_wrap && ny == 0;  // desk_g <= desk_q here: ry starts at that -top
    wire        n_in_raster = n_raster_y < rows;
    wire        n_in_x = !desk_g || (nx >= D_LEFT && nx < D_LEFT + ZM_DESK_WIDTH);
    // The output line after this one, for the HBL announced in its blank (nx = 800: ny = out_y).
    wire        ny1_in_raster = ry1 < rows;
    wire        n_vbl = (nx == 0) && (ny == ZM_BOTTOM);

    always @(posedge clk) begin
        if (rst) begin
            out_x <= H_TOTAL - 1;  // so the first clock after reset is (0, 0)
            out_y <= V_TOTAL - 1;
            {hsync, vsync, de, zm_active, zm_hbl, zm_vbl, desk_q, desk_g} <= 8'b0;
            zm_hbl_line <= 9'd0;
            zm_x <= 10'd0;
            zm_line <= 9'd0;
        end else begin
            out_x <= nx;
            out_y <= ny;
            ry <= n_raster_y;
            hsync <= (nx >= H_ACTIVE + H_FP) && (nx < H_ACTIVE + H_FP + H_SYNC);
            vsync <= (ny >= V_ACTIVE + V_FP) && (ny < V_ACTIVE + V_FP + V_SYNC);
            de <= (nx < H_ACTIVE) && (ny < V_ACTIVE);
            zm_active <= n_in_raster && (nx < H_ACTIVE) && n_in_x;
            zm_x <= desk_g ? nx[9:0] - D_LEFT[9:0] : nx[9:0];
            if (n_in_raster) zm_line <= desk_g ? n_raster_y[8:0] : n_raster_y[9:1];
            // HBL: the first blank clock of the output line before a new raster line.
            zm_hbl <= (nx == H_ACTIVE) && ny1_in_raster && (desk_g || !ry1[0]);
            if ((nx == H_ACTIVE) && ny1_in_raster) zm_hbl_line <= desk_g ? ry1[8:0] : ry1[9:1];
            zm_vbl <= n_vbl;
            if (n_vbl) desk_q <= desk;
            if (frame_start) desk_g <= desk_q;
        end
    end
endmodule

`default_nettype wire
