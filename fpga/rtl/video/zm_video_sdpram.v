// Simple dual-port RAM: one write port with byte enables, one registered read
// port (data the clock after the address). Written in the shape Yosys infers as
// block RAM (or LUT RAM when small), so every buffer in the compositor costs
// what the synthesis report says and nothing hides in flip-flops.
//
// Two shapes, the same behaviour (the testbenches see no difference):
// - ONE array with byte write enables (the default since the LUT diet, 2026-11-11): Vivado maps
//   it to the fewest block RAMs the geometry allows (a 256 x 64 buffer is one RAMB36, not eight
//   RAMB18 holding 2 Kbit each). Vivado is the board toolchain (fpga/README.md).
// - `ZM_SDPRAM_LANES`: one 8-bit array per byte lane, each its own block RAM. BOARD (2026-10-04,
//   openXC7 / prjxray bitstream): wider shapes lost data there: a 48/64-bit array (one RAMB36 in
//   SDP x72 mode) lost bits 0-35; 32-bit SDP x36 and 16-bit TDP x18 slices with per-byte write
//   enables lost whole byte lanes at fixed positions. The shapes proven on the board under openXC7
//   write one enable per primitive or are byte-wide (docs/FPGA_STEPS.md). An openXC7 build
//   defines ZM_SDPRAM_LANES (soc/openxc7.py).
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
    output wire [DW-1:0]     rdata
);
`ifdef ZM_SDPRAM_LANES
    localparam integer SW = 8;                     // the slice width: one byte lane per array
    localparam integer NS = (DW + SW - 1) / SW;    // slices (the last may be narrower)

    genvar s;
    generate
        for (s = 0; s < NS; s = s + 1) begin : g_slice
            localparam integer LO = s * SW;
            localparam integer W = (DW - LO) < SW ? (DW - LO) : SW;
            (* ram_style = "block" *) reg [W-1:0] mem [0:(1 << AW) - 1];
            reg [W-1:0] q;
            integer i;
            always @(posedge clk) begin
                for (i = 0; i < W / 8; i = i + 1)
                    if (we[LO / 8 + i]) mem[waddr][i*8 +: 8] <= wdata[LO + i*8 +: 8];
                q <= mem[raddr];
            end
            assign rdata[LO +: W] = q;
        end
    endgenerate
`else
    (* ram_style = "block" *) reg [DW-1:0] mem [0:(1 << AW) - 1];
    reg [DW-1:0] q;
    integer i;
    always @(posedge clk) begin
        for (i = 0; i < DW / 8; i = i + 1)
            if (we[i]) mem[waddr][i*8 +: 8] <= wdata[i*8 +: 8];
        q <= mem[raddr];
    end
    assign rdata = q;
`endif
endmodule

`default_nettype wire
