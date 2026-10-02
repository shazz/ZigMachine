// The first bitstream: proves the openXC7 flow, the board's PL clock and its
// LEDs before anything of ours goes on the board. PL_CLK_50M (N18) is divided
// to ~1 Hz on PL_LED1 (P15) and PL_LED2 (U12). Both LEDs are active LOW, and
// LED2 is driven in counter-phase, so exactly one is lit at any time.
// Port names are the board.xdc's, so its constraints apply as they are.
`default_nettype none

module blink_top (
    input  wire PL_CLK_50M,
    output wire PL_LED1,
    output wire PL_LED2
);
    localparam integer HALF_PERIOD = 25_000_000;  // 0.5 s at 50 MHz

    reg [24:0] count = 25'd0;
    reg        phase = 1'b0;

    always @(posedge PL_CLK_50M) begin
        if (count == HALF_PERIOD - 1) begin
            count <= 25'd0;
            phase <= ~phase;
        end else begin
            count <= count + 25'd1;
        end
    end

    assign PL_LED1 = ~phase;  // lit (low) in the phase = 1 half
    assign PL_LED2 = phase;   // lit in the other half
endmodule

`default_nettype wire
