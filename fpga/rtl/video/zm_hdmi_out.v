// HDMI out with the machine's sound: the board SoC's picture (the scanout plus
// the glass OSD, as zm_dvi_out takes it) and the audio core's 44.1 kHz stereo
// samples (zm_audio_soc, in the system clock domain), as four TMDS pairs. The
// samples cross into the pixel domain through zm_audio_fifo and ride in data
// islands (zm_hdmi_tx: N 6272, the CTS measured, 44444 / 44445 at 40 MHz), the
// shape ym-test proved on the board (snd_lab_out + ym_test_top). Serialised as
// zm_dvi_out's default: a fabric shifter at 5x into an ODDR (zm_oddr10). The
// sample rates on both sides must be the same exact fraction of the one crystal
// (soc/zm_audio_soc.py derives the core's from the system clock).
// `fault` (sticky, pixel domain): {island queue overflow, FIFO underflow, FIFO overflow}.
// Board only: it instantiates Xilinx primitives.
`default_nettype none

module zm_hdmi_out (
    input  wire        sys_clk,
    input  wire        sys_rst,
    input  wire        smp_valid,
    input  wire [15:0] smp_l,
    input  wire [15:0] smp_r,
    input  wire        pix_clk,
    input  wire        pix5x_clk,
    input  wire        pix_rst,
    input  wire [7:0]  r,
    input  wire [7:0]  g,
    input  wire [7:0]  b,
    input  wire        de,
    input  wire        hsync,
    input  wire        vsync,
    output wire [3:0]  tmds_p,             // {clock, red, green, blue}
    output wire [3:0]  tmds_n,
    output wire [2:0]  fault
);
    wire        req, played, overflow, underflow, aud_overflow;
    wire [31:0] data;
    zm_audio_fifo u_fifo (
        .wclk(sys_clk), .wrst(sys_rst), .winc(smp_valid), .wdata({smp_l, smp_r}), .overflow(overflow),
        .rclk(pix_clk), .rrst(pix_rst), .rreq(req), .rvalid(played), .rdata(data), .underflow(underflow));

    wire [29:0] sym;
    zm_hdmi_tx #(.RATE_INC(441), .RATE_MOD(400000), .ACR_N(20'd6272), .CS_48K(1'b0)) u_tx (
        .clk(pix_clk), .rst(pix_rst), .r(r), .g(g), .b(b), .de(de), .hsync(hsync), .vsync(vsync),
        .aud_req(req), .aud_valid(played), .aud_l(data[31:16]), .aud_r(data[15:0]),
        .sym(sym), .aud_overflow(aud_overflow));
    assign fault = {aud_overflow, underflow, overflow};

    wire [39:0] sym4 = {10'b0000011111, sym};
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : ch
            wire serial;
            zm_oddr10 u_ser (.clk(pix5x_clk), .d(sym4[i * 10 +: 10]), .q(serial));
            OBUFDS u_buf (.I(serial), .O(tmds_p[i]), .OB(tmds_n[i]));
        end
    endgenerate
endmodule

`default_nettype wire
