// The HDMI audio bitstream minus its clocks and serialisers (those are in
// rtl/board/hdmi_audio_top.v): the bring-up test pattern (rtl/board/hdmi_pattern.v)
// and the test tone (rtl/board/hdmi_tone.v) through the HDMI transmitter
// (rtl/hdmi/zm_hdmi_tx.v). The source's video and samples also leave on the
// `src_*` ports, for tests/tb/hdmi_audio_tb.cpp to compare with what it decodes.
`default_nettype none

module hdmi_audio_core #(
    parameter integer RATE_INC = 3,            // 48 kHz at 40 MHz (44.1 kHz: 441 / 400000)
    parameter integer RATE_MOD = 2500,
    parameter [19:0]  ACR_N = 20'd6144,        // 6272 at 44.1 kHz
    parameter         CS_48K = 1'b1,
    parameter [31:0]  INC_L = 32'd39370534,    // the tone's 440 / 660 Hz at that rate
    parameter [31:0]  INC_R = 32'd59055800
) (
    input  wire        clk,             // pixel clock, 40 MHz
    input  wire        rst,
    output wire [29:0] sym,             // TMDS {channel 2, channel 1, channel 0}
    output wire        aud_overflow,
    output wire [7:0]  src_r, src_g, src_b,
    output wire        src_de, src_hs, src_vs,
    output wire        src_valid,
    output wire [15:0] src_l, src_r16
);
    hdmi_pattern u_pat (.clk(clk), .rst(rst), .r(src_r), .g(src_g), .b(src_b),
                        .de(src_de), .hsync(src_hs), .vsync(src_vs));
    wire req;
    hdmi_tone #(.INC_L(INC_L), .INC_R(INC_R)) u_tone (
        .clk(clk), .rst(rst), .req(req), .valid(src_valid), .left(src_l), .right(src_r16));
    zm_hdmi_tx #(.RATE_INC(RATE_INC), .RATE_MOD(RATE_MOD), .ACR_N(ACR_N), .CS_48K(CS_48K)) u_tx (
        .clk(clk), .rst(rst), .r(src_r), .g(src_g), .b(src_b), .de(src_de), .hsync(src_hs), .vsync(src_vs),
        .aud_req(req), .aud_valid(src_valid), .aud_l(src_l), .aud_r(src_r16), .sym(sym), .aud_overflow(aud_overflow));
endmodule

`default_nettype wire
