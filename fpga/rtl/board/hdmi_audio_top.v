// Fourth bitstream: HDMI (not DVI) on HDMI1, with sound. The bring-up test
// pattern at 800x600@60 plus a 48 kHz stereo test tone, 440 Hz left and 660 Hz
// right at -12 dBFS, carried in data islands (rtl/board/hdmi_audio_core.v,
// rtl/hdmi/). The Z7-Lite has no other audio output: the monitor (or a TV, an
// AV receiver) plays it. Serialised like zm_dvi_out's default, the one proven on
// the board: a fabric shifter at 200 MHz into an ODDR, two bits a clock.
// LEDs (active low): PL_LED1 toggles every 24000 samples (a 1 Hz blink proves
// the 48 kHz sample clock), PL_LED2 lit while the PLL is locked; PL_LED1 stays
// lit if a sample was ever dropped (it should never happen).
`default_nettype none

module hdmi_audio_top (
    input  wire PL_CLK_50M,
    output wire PL_LED1,
    output wire PL_LED2,
    output wire HDMI1_CLK_P,
    output wire HDMI1_CLK_N,
    output wire HDMI1_D0_P,
    output wire HDMI1_D0_N,
    output wire HDMI1_D1_P,
    output wire HDMI1_D1_N,
    output wire HDMI1_D2_P,
    output wire HDMI1_D2_N
);
    wire pix_clk, pix5x_clk, locked, rst;
    hdmi_clk u_clk (.PL_CLK_50M(PL_CLK_50M), .pix_clk(pix_clk), .pix5x_clk(pix5x_clk), .locked(locked), .rst(rst));

    wire [29:0] sym;
    wire        overflow, valid;
    hdmi_audio_core u_core (
        .clk(pix_clk), .rst(rst), .sym(sym), .aud_overflow(overflow),
        .src_r(), .src_g(), .src_b(), .src_de(), .src_hs(), .src_vs(),
        .src_valid(valid), .src_l(), .src_r16());

    wire [39:0] sym4 = {10'b0000011111, sym};  // {clock, red, green, blue}
    wire [3:0]  tmds_p, tmds_n;
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : ch
            wire serial;
            zm_oddr10 u_ser (.clk(pix5x_clk), .d(sym4[i * 10 +: 10]), .q(serial));
            OBUFDS u_buf (.I(serial), .O(tmds_p[i]), .OB(tmds_n[i]));
        end
    endgenerate
    assign {HDMI1_CLK_P, HDMI1_D2_P, HDMI1_D1_P, HDMI1_D0_P} = tmds_p;
    assign {HDMI1_CLK_N, HDMI1_D2_N, HDMI1_D1_N, HDMI1_D0_N} = tmds_n;

    reg [14:0] samples = 15'd0;
    reg        phase = 1'b0;
    always @(posedge pix_clk) begin
        if (valid) begin
            samples <= (samples == 15'd23999) ? 15'd0 : samples + 15'd1;
            if (samples == 15'd23999) phase <= ~phase;
        end
    end
    assign PL_LED1 = ~(phase || overflow);
    assign PL_LED2 = ~locked;
endmodule

`default_nettype wire
