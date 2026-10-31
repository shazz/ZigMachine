// LINE sequencer: Bresenham from (x0,y0) to (x1,y1) (the core combines COLOR with the
// destination through MINTERM). One step per clock for a pixel outside the clip (it is skipped), one
// per accepted pixel inside; every step, clipped or not, counts for CYCLES (`step`).
// The tie-break is the Zig machine's: e2 = 2*err; x steps when e2 >= dy, y when e2 <= dx,
// both tests on the same e2.
`default_nettype none

module zm_blit_line (
    input  wire               clk,
    input  wire               rst,
    input  wire               go,
    input  wire signed [17:0] x0, y0, x1, y1, cx0, cy0, cx1, cy1,
    output wire               px_valid,
    output wire signed [17:0] px_x, px_y,
    input  wire               px_ready,
    output wire               step,
    output reg                done
);
    reg run;
    reg signed [17:0] x, y;
    reg signed [19:0] err;
    // dx, dy and the steps are functions of registers that hold still while BUSY: copies a clock
    // behind are exact by `go` (the checks run first), and keep the subtract, the abs and the
    // error's add out of one clock (-1.1 ns at 125 MHz out of context, 2026-10-31)
    reg signed [19:0] dx, dy;
    reg signed [17:0] sx, sy;
    always @(posedge clk) begin
        dx <= x1 >= x0 ? x1 - x0 : x0 - x1;
        dy <= y1 >= y0 ? y0 - y1 : y1 - y0;
        sx <= x0 < x1 ? 18'sd1 : -18'sd1;
        sy <= y0 < y1 ? 18'sd1 : -18'sd1;
    end
    wire signed [19:0] e2 = err <<< 1;
    wire mx = e2 >= dy, my = e2 <= dx;
    wire inclip = x >= cx0 && x < cx1 && y >= cy0 && y < cy1;
    assign px_valid = run && inclip;
    assign px_x = x;
    assign px_y = y;
    assign step = run && (!inclip || px_ready);

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) run <= 1'b0;
        else if (go) begin
            run <= 1'b1; x <= x0; y <= y0; err <= dx + dy;
        end else if (step) begin
            if (x == x1 && y == y1) begin run <= 1'b0; done <= 1'b1; end
            err <= err + (mx ? dy : 20'sd0) + (my ? dx : 20'sd0);
            if (mx) x <= x + sx;
            if (my) y <= y + sy;
        end
    end
endmodule
