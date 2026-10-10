// A clock enable at f_clk x INC / MOD on average, from a fractional
// accumulator: never two clocks running (INC < MOD), exact over any whole
// number of MOD clocks. The audio core's sample strobe (44.1 kHz at 50 MHz:
// 441 / 500000) and the YM's 2 MHz (1 / 25) both come from one of these, so a
// sample period always holds 45 or 46 YM clocks (2 MHz / 44.1 kHz = 45.35).
`default_nettype none

module zm_audio_frac #(
    parameter integer INC = 1,
    parameter integer MOD = 25
) (
    input  wire clk,
    input  wire rst,
    output reg  tick = 1'b0
);
    reg  [23:0] acc = 24'd0;
    wire [24:0] next = {1'b0, acc} + INC;
    wire        hit = next >= MOD;

    always @(posedge clk) begin
        if (rst) begin
            acc <= 24'd0;
            tick <= 1'b0;
        end else begin
            acc <= hit ? next - MOD : next[23:0];
            tick <= hit;
        end
    end
endmodule

`default_nettype wire
