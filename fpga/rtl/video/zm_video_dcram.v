// Simple dual-port RAM with a clock per port: written in one domain, read
// (registered, data the clock after the address) in another. This is the
// clock-domain crossing of the display line buffers: block RAM ports are
// independent, so the data needs no synchroniser, only the protocol that says
// when a line is complete (zm_video_scan.v's toggles). `we` has a bit per
// LW-bit lane of a word: one lane (the default) is a whole-word write; the
// palette mirror (zm_video_desk.v) writes byte lanes, as a byte store to a
// palette word does.
`default_nettype none

module zm_video_dcram #(
    parameter integer AW = 10,
    parameter integer DW = 48,
    parameter integer LW = DW
) (
    input  wire          wclk,
    input  wire [DW/LW-1:0] we,
    input  wire [AW-1:0] waddr,
    input  wire [DW-1:0] wdata,
    input  wire          rclk,
    input  wire [AW-1:0] raddr,
    output reg  [DW-1:0] rdata
);
    reg [DW-1:0] mem [0:(1 << AW) - 1];

    integer i;
    always @(posedge wclk)
        for (i = 0; i < DW / LW; i = i + 1)
            if (we[i]) mem[waddr][i * LW +: LW] <= wdata[i * LW +: LW];

    always @(posedge rclk)
        rdata <= mem[raddr];
endmodule

`default_nettype wire
