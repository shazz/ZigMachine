// ZigMachine video timing: VESA 800x600 @ 60 Hz (40 MHz pixel clock) carrying
// the machine's 800x280 raster (memmap RASTER_WIDTH x RASTER_HEIGHT) with every
// raster line shown twice, centred vertically (20 blank output lines above and
// below). Horizontally the raster is already 800 wide (low res is pixel-doubled
// into it), so x maps 1:1.
//
// The HBL strobe `zm_hbl` fires once per RASTER line, at the start of the
// horizontal blank BEFORE that line's first output line, with `zm_hbl_line`
// naming the line about to be drawn. A handler or a copper list therefore has
// the whole blank (264 clocks) to change a palette register before pixel 0.
// `zm_vbl` fires once a frame, at pixel 0 of the first output line after the
// raster.
`default_nettype none

module zm_vtiming (
    input  wire        clk,            // pixel clock, 40 MHz
    input  wire        rst,
    output reg         hsync,          // positive polarity (VESA 800x600@60)
    output reg         vsync,          // positive polarity
    output reg         de,             // output-frame display enable (800x600)
    output reg  [10:0] out_x,          // 0..1055
    output reg  [9:0]  out_y,          // 0..627
    output reg         zm_active,      // inside the 800x280 raster (doubled)
    output reg  [9:0]  zm_x,           // raster x, 0..799 while zm_active
    output reg  [8:0]  zm_line,        // raster line, 0..279 while zm_active
    output reg         zm_hbl,         // one-clock HBL strobe per raster line
    output reg  [8:0]  zm_hbl_line,    // the raster line zm_hbl announces
    output reg         zm_vbl          // one-clock strobe per frame
);
`include "memmap.vh"

    localparam integer H_ACTIVE = 800, H_FP = 40, H_SYNC = 128, H_BP = 88;
    localparam integer V_ACTIVE = 600, V_FP = 1, V_SYNC = 4, V_BP = 23;
    localparam integer H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;  // 1056
    localparam integer V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;  // 628
    localparam integer ZM_TOP = (V_ACTIVE - 2 * ZM_RASTER_HEIGHT) / 2;  // 20
    localparam integer ZM_BOTTOM = ZM_TOP + 2 * ZM_RASTER_HEIGHT;       // 580

    // The next pixel's position, registered below so every output is aligned.
    wire        h_wrap = (out_x == H_TOTAL - 1);
    wire [10:0] nx = h_wrap ? 11'd0 : out_x + 11'd1;
    wire [9:0]  ny = !h_wrap ? out_y : (out_y == V_TOTAL - 1) ? 10'd0 : out_y + 10'd1;
    wire        n_in_raster = (ny >= ZM_TOP) && (ny < ZM_BOTTOM);
    wire [9:0]  n_raster_y = ny - ZM_TOP[9:0];
    // The output line after ny, for the HBL announced in ny's blank.
    wire [9:0]  ny1 = (ny == V_TOTAL - 1) ? 10'd0 : ny + 10'd1;
    wire        ny1_in_raster = (ny1 >= ZM_TOP) && (ny1 < ZM_BOTTOM);
    wire [9:0]  ny1_raster_y = ny1 - ZM_TOP[9:0];

    always @(posedge clk) begin
        if (rst) begin
            out_x <= H_TOTAL - 1;  // so the first clock after reset is (0, 0)
            out_y <= V_TOTAL - 1;
            {hsync, vsync, de, zm_active, zm_hbl, zm_vbl} <= 6'b0;
            zm_hbl_line <= 9'd0;
            zm_x <= 10'd0;
            zm_line <= 9'd0;
        end else begin
            out_x <= nx;
            out_y <= ny;
            hsync <= (nx >= H_ACTIVE + H_FP) && (nx < H_ACTIVE + H_FP + H_SYNC);
            vsync <= (ny >= V_ACTIVE + V_FP) && (ny < V_ACTIVE + V_FP + V_SYNC);
            de <= (nx < H_ACTIVE) && (ny < V_ACTIVE);
            zm_active <= n_in_raster && (nx < H_ACTIVE);
            zm_x <= nx[9:0];
            if (n_in_raster) zm_line <= n_raster_y[9:1];
            // HBL: the first blank clock of the output line before a new raster line.
            zm_hbl <= (nx == H_ACTIVE) && ny1_in_raster && !ny1_raster_y[0];
            if ((nx == H_ACTIVE) && ny1_in_raster) zm_hbl_line <= ny1_raster_y[9:1];
            zm_vbl <= (nx == 0) && (ny == ZM_BOTTOM);
        end
    end
endmodule

`default_nettype wire
