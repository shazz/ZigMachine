// Simple dual-port RAM: one write port with byte enables, one registered read
// port (data the clock after the address). Written in the shape Yosys infers as
// block RAM (or LUT RAM when small), so every buffer in the compositor costs
// what the synthesis report says and nothing hides in flip-flops.
`default_nettype none

module zm_video_sdpram #(
    parameter integer AW = 8,   // address bits
    parameter integer DW = 32   // data bits, a multiple of 8
) (
    input  wire              clk,
    input  wire [DW/8-1:0]   we,      // one enable per byte lane
    input  wire [AW-1:0]     waddr,
    input  wire [DW-1:0]     wdata,
    input  wire [AW-1:0]     raddr,
    output reg  [DW-1:0]     rdata
);
    reg [DW-1:0] mem [0:(1 << AW) - 1];
    integer i;

    always @(posedge clk) begin
        for (i = 0; i < DW / 8; i = i + 1)
            if (we[i]) mem[waddr][i*8 +: 8] <= wdata[i*8 +: 8];
        rdata <= mem[raddr];
    end
endmodule

`default_nettype wire
