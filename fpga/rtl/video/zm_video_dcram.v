// Simple dual-port RAM with a clock per port: written in one domain, read
// (registered, data the clock after the address) in another. This is the
// clock-domain crossing of the display line buffers: block RAM ports are
// independent, so the data needs no synchroniser, only the protocol that says
// when a line is complete (zm_video_scan.v's toggles).
`default_nettype none

module zm_video_dcram #(
    parameter integer AW = 10,
    parameter integer DW = 48
) (
    input  wire          wclk,
    input  wire          we,
    input  wire [AW-1:0] waddr,
    input  wire [DW-1:0] wdata,
    input  wire          rclk,
    input  wire [AW-1:0] raddr,
    output reg  [DW-1:0] rdata
);
    reg [DW-1:0] mem [0:(1 << AW) - 1];

    always @(posedge wclk)
        if (we) mem[waddr] <= wdata;

    always @(posedge rclk)
        rdata <= mem[raddr];
endmodule

`default_nettype wire
