// The ym-test bitstream minus its clocks and serialisers (rtl/board/ym_test_top.v):
// the YM dump playing through the audio core in the system domain
// (ym_test_audio) and out over HDMI with the test pattern (snd_lab_out). The
// system side's samples also leave on `src_*`, for tests/tb/ym_test_tb.cpp to
// compare with what the HDMI sink decodes.
`default_nettype none
`ifndef YM_WORDS
`define YM_WORDS 22678
`endif

module ym_test_core #(
    parameter integer WORDS = `YM_WORDS   // the ROM's depth (see ym_test_audio)
) (
    input  wire        sys_clk,          // 50 MHz
    input  wire        sys_rst,
    input  wire        pix_clk,          // 40 MHz
    input  wire        pix_rst,
    output wire [29:0] sym,
    output wire        played,           // pixel domain: a sample went out
    output wire [15:0] played_l, played_r,
    output wire [2:0]  fault,
    output wire [2:0]  status,           // system domain: zm_audio_core's
    output wire        src_valid,
    output wire [15:0] src_l, src_r,
    output wire [15:0] pc
);
    ym_test_audio #(.WORDS(WORDS)) u_audio (
        .clk(sys_clk), .rst(sys_rst), .smp_valid(src_valid), .smp_l(src_l), .smp_r(src_r),
        .status(status), .pc(pc));
    snd_lab_out u_out (
        .sys_clk(sys_clk), .sys_rst(sys_rst), .smp_valid(src_valid), .smp_l(src_l), .smp_r(src_r),
        .pix_clk(pix_clk), .pix_rst(pix_rst), .sym(sym), .played(played), .played_l(played_l),
        .played_r(played_r), .fault(fault));
endmodule

`default_nettype wire
