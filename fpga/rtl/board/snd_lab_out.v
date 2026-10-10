// The output half of a sound-chip lab player (docs/FPGA_AUDIO.md), chip-
// agnostic: stereo 16-bit samples made in the system clock domain cross into
// the pixel domain (zm_audio_fifo) and leave over HDMI at 44.1 kHz in data
// islands (zm_hdmi_tx: N 6272, the CTS measured, 44444 / 44445), with the
// bring-up test pattern (hdmi_pattern) as the picture. The sample rate here and
// the system side's must be the same exact fraction of the one crystal.
// `played` pulses (pixel domain) for each sample sent; `fault` is sticky: the
// FIFO overflowed or ran dry, or the island queue overflowed.
`default_nettype none

module snd_lab_out (
    input  wire        sys_clk,
    input  wire        sys_rst,
    input  wire        smp_valid,
    input  wire [15:0] smp_l,
    input  wire [15:0] smp_r,
    input  wire        pix_clk,
    input  wire        pix_rst,
    output wire [29:0] sym,
    output wire        played,
    output wire [15:0] played_l,
    output wire [15:0] played_r,
    output wire [2:0]  fault           // {island queue, FIFO underflow, FIFO overflow}
);
    wire        req, overflow, underflow, aud_overflow;
    wire [31:0] data;
    zm_audio_fifo u_fifo (
        .wclk(sys_clk), .wrst(sys_rst), .winc(smp_valid), .wdata({smp_l, smp_r}), .overflow(overflow),
        .rclk(pix_clk), .rrst(pix_rst), .rreq(req), .rvalid(played), .rdata(data), .underflow(underflow));
    assign {played_l, played_r} = data;

    wire [7:0] r, g, b;
    wire       de, hs, vs;
    hdmi_pattern u_pat (.clk(pix_clk), .rst(pix_rst), .r(r), .g(g), .b(b), .de(de), .hsync(hs), .vsync(vs));
    zm_hdmi_tx #(.RATE_INC(441), .RATE_MOD(400000), .ACR_N(20'd6272), .CS_48K(1'b0)) u_tx (
        .clk(pix_clk), .rst(pix_rst), .r(r), .g(g), .b(b), .de(de), .hsync(hs), .vsync(vs),
        .aud_req(req), .aud_valid(played), .aud_l(played_l), .aud_r(played_r),
        .sym(sym), .aud_overflow(aud_overflow));
    assign fault = {aud_overflow, underflow, overflow};
endmodule

`default_nettype wire
