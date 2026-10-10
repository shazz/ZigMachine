// Behavioural models of the Xilinx cells rtl/board/prim_test/ instantiates
// (LUT6, MUXF7, MUXF8), for its CXXRTL simulation only: the bitstream build
// takes the real cells from synth_xilinx's library.
`default_nettype none

module LUT6 #(parameter [63:0] INIT = 64'd0) (
    input wire I0, I1, I2, I3, I4, I5,
    output wire O
);
    assign O = INIT[{I5, I4, I3, I2, I1, I0}];
endmodule

module MUXF7 (input wire I0, I1, S, output wire O);
    assign O = S ? I1 : I0;
endmodule

module MUXF8 (input wire I0, I1, S, output wire O);
    assign O = S ? I1 : I0;
endmodule

`default_nettype wire
