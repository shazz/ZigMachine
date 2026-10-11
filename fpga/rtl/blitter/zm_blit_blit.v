// BLIT sequencer: the clipped W x H box, rows then columns, ascending or (CON.DESC)
// descending, so an overlapping copy walks the way the Zig machine does. Pixel (i, j) of
// the rectangle reads A/B at base + j*stride + i and writes the destination at the same
// (x, y) = (x0 + i, y0 + j). The box (ex0..ey1) is the rectangle cut by the clip, so every
// pixel issued is visible; the pixel unit applies the key and the minterm.
`default_nettype none

module zm_blit_blit (
    input  wire               clk,
    input  wire               rst,
    input  wire               go,
    input  wire [22:0]        a_lin, b_lin,
    input  wire [15:0]        a_stride, b_stride,
    input  wire               desc,
    input  wire signed [17:0] x0, y0, ex0, ey0, ex1, ey1,
    output wire               px_valid,
    output wire signed [17:0] px_x, px_y,
    output wire [22:0]        px_aaddr, px_baddr,
    input  wire               px_ready,
    output reg                done
);
    reg run;
    reg signed [17:0] x, y;
    wire signed [17:0] xs = desc ? ex1 - 18'sd1 : ex0, xe = desc ? ex0 : ex1 - 18'sd1;
    wire signed [17:0] ys = desc ? ey1 - 18'sd1 : ey0, ye = desc ? ey0 : ey1 - 18'sd1;
    // A and B at (x - x0, y - y0) of their rectangles, walked with y (zm_blit_row)
    zm_blit_row ra (.clk(clk), .base(a_lin), .stride(a_stride), .xorg(x0), .yorg(y0), .ys(ys), .dn(desc),
        .ld(go), .y(y), .x(x), .addr(px_aaddr));
    zm_blit_row rb (.clk(clk), .base(b_lin), .stride(b_stride), .xorg(x0), .yorg(y0), .ys(ys), .dn(desc),
        .ld(go), .y(y), .x(x), .addr(px_baddr));
    assign px_valid = run;
    assign px_x = x;
    assign px_y = y;

    wire signed [17:0] step = desc ? -18'sd1 : 18'sd1;
    wire last_x = x == xe, last_y = y == ye;
    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) run <= 1'b0;
        else if (go) begin
            x <= xs; y <= ys;
            if (ex1 <= ex0 || ey1 <= ey0) done <= 1'b1;
            else run <= 1'b1;
        end else if (run && px_ready) begin
            x <= last_x ? xs : x + step;
            if (last_x) y <= y + step;
            if (last_x && last_y) begin run <= 1'b0; done <= 1'b1; end
        end
    end
endmodule
