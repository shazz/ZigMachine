// FILL sequencer: the clipped W x H box of the destination, row by row, COLOR or the
// halftone pick. With CON2.FILL_MT the value is channel B and the destination channel C
// (D = LF(0, v, D)); without it, MT_B, which is a plain write and reads nothing.
// The box (ex0..ey1) comes from zm_blit_chk; CYCLES (W*H, clipped pixels included) is
// the core's business.
`default_nettype none

module zm_blit_fill (
    input  wire               clk,
    input  wire               rst,
    input  wire               go,
    input  wire [7:0]         color, bg, mt,
    input  wire               fill_mt, ht_on, ht_bit,
    input  wire signed [17:0] ex0, ey0, ex1, ey1,
    output wire [3:0]         hx, hy,
    output wire               px_valid,
    output wire signed [17:0] px_x, px_y,
    output wire [7:0]         px_bimm, px_mt,
    input  wire               px_ready,
    output reg                done
);
    reg run;
    reg signed [17:0] x, y;
    wire combine = fill_mt && mt != 8'hCC;  // ZM_MT_B: the plain write
    assign px_x = x;
    assign px_y = y;
    assign px_valid = run;
    assign px_bimm = ht_on ? (ht_bit ? color : bg) : color;
    assign px_mt = combine ? mt : 8'hCC;
    assign hx = x[3:0];
    assign hy = y[3:0];

    wire last_x = x == ex1 - 18'sd1, last_y = y == ey1 - 18'sd1;
    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) run <= 1'b0;
        else if (go) begin
            x <= ex0; y <= ey0;
            if (ex1 <= ex0 || ey1 <= ey0) done <= 1'b1;
            else run <= 1'b1;
        end else if (run && px_ready) begin
            x <= last_x ? ex0 : x + 18'sd1;
            if (last_x) y <= y + 18'sd1;
            if (last_x && last_y) begin run <= 1'b0; done <= 1'b1; end
        end
    end
endmodule
