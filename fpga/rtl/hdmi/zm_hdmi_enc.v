// The three HDMI TMDS channels (HDMI 1.3a section 5.4): video by the DVI encoder
// (rtl/video/zm_tmds_enc.v), every other period's symbols chosen here.
//   control   zm_tmds_enc's tokens; channel 0 carries {VSYNC, HSYNC}, channels
//             1 and 2 {CTL1, CTL0} and {CTL3, CTL2}: CTL0 = 1 in both preambles,
//             CTL2 = 1 in the data island one (section 5.2.1.1)
//   vguard    the video leading guard band: 1011001100 on channels 0 and 2,
//             0100110011 on channel 1 (section 5.2.2.1)
//   dguard    the data island guard bands: TERC4 of `nib` on channel 0 (the
//             island module puts {1, 1, VSYNC, HSYNC} there), 0100110011 on 1 and 2
//   ddata     a packet pixel: TERC4 of each channel's nibble (section 5.4.3)
// The encoder resets its disparity whenever DE is low, as HDMI requires outside
// video. Symbols leave two clocks after their inputs, like zm_tmds_enc's.
`default_nettype none

module zm_hdmi_enc (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  r, g, b,
    input  wire        de, hs, vs,
    input  wire        vpre, dpre,      // preambles
    input  wire        vguard, dguard, ddata,
    input  wire [11:0] nib,             // {channel 2, channel 1, channel 0}
    output wire [29:0] sym              // {channel 2, channel 1, channel 0}
);
    localparam [9:0] GB_A = 10'b1011001100, GB_B = 10'b0100110011;

    function [9:0] terc4(input [3:0] d);
        case (d)
            4'h0: terc4 = 10'b1010011100;
            4'h1: terc4 = 10'b1001100011;
            4'h2: terc4 = 10'b1011100100;
            4'h3: terc4 = 10'b1011100010;
            4'h4: terc4 = 10'b0101110001;
            4'h5: terc4 = 10'b0100011110;
            4'h6: terc4 = 10'b0110001110;
            4'h7: terc4 = 10'b0100111100;
            4'h8: terc4 = 10'b1011001100;
            4'h9: terc4 = 10'b0100111001;
            4'hA: terc4 = 10'b0110011100;
            4'hB: terc4 = 10'b1011000110;
            4'hC: terc4 = 10'b1010001110;
            4'hD: terc4 = 10'b1001110001;
            4'hE: terc4 = 10'b0101100011;
            default: terc4 = 10'b1011000011;
        endcase
    endfunction

    wire [29:0] q;
    zm_tmds_enc u_0 (.clk(clk), .rst(rst), .de(de), .d(b), .c({vs, hs}), .q(q[9:0]));
    zm_tmds_enc u_1 (.clk(clk), .rst(rst), .de(de), .d(g), .c({1'b0, vpre || dpre}), .q(q[19:10]));
    zm_tmds_enc u_2 (.clk(clk), .rst(rst), .de(de), .d(r), .c({1'b0, dpre}), .q(q[29:20]));

    wire [29:0] o = vguard ? {GB_A, GB_B, GB_A}
                  : dguard ? {GB_B, GB_B, terc4(nib[3:0])}
                  : {terc4(nib[11:8]), terc4(nib[7:4]), terc4(nib[3:0])};
    reg  [29:0] o1 = 30'd0, o2 = 30'd0;
    reg         v1 = 1'b0, v2 = 1'b0;
    always @(posedge clk) {o1, v1, o2, v2} <= {o, vguard || dguard || ddata, o1, v1};
    assign sym = v2 ? o2 : q;
endmodule

`default_nettype wire
