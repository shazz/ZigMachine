// Test top for tests/tb/hdmi_audio44_tb.cpp: rtl/board/hdmi_audio_core.v at
// 44.1 kHz on the 40 MHz pixel clock (zm_hdmi_acr: 441 / 400000, N 6272).
`default_nettype none

module hdmi_audio44 (
    input  wire        clk,
    input  wire        rst,
    output wire [29:0] sym,
    output wire        aud_overflow,
    output wire [7:0]  src_r, src_g, src_b,
    output wire        src_de, src_hs, src_vs,
    output wire        src_valid,
    output wire [15:0] src_l, src_r16
);
    hdmi_audio_core #(
        .RATE_INC(441), .RATE_MOD(400000), .ACR_N(20'd6272), .CS_48K(1'b0),
        .INC_L(32'd42852281), .INC_R(32'd64278422)
    ) u_core (
        .clk(clk), .rst(rst), .sym(sym), .aud_overflow(aud_overflow),
        .src_r(src_r), .src_g(src_g), .src_b(src_b), .src_de(src_de), .src_hs(src_hs), .src_vs(src_vs),
        .src_valid(src_valid), .src_l(src_l), .src_r16(src_r16));
endmodule

`default_nettype wire
