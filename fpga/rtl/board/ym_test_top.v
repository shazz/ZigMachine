// Fifth bitstream (`make ym-test`): the YM2149 playing a real tune over HDMI.
// jt49 (the machine's audio core, rtl/audio/) plays "Drooling" by 505, a YM5
// register dump (docs/music/union/Drooling.ymraw, 6,433 frames, 2:08, looped)
// held in BRAM as register writes (tools/ym_rom.py, rtl/board/zm_dump_player.v),
// 44.1 kHz stereo in HDMI data islands, with the bring-up test pattern on screen
// (rtl/board/ym_test_core.v). Serialised as the proven audio bitstream: a
// fabric shifter at 200 MHz into an ODDR, two bits a clock.
// LEDs (active low): PL_LED1 changes every 22,050 samples sent (a 1 Hz blink is
// the 44.1 kHz sample clock) and stays lit on a fault (the clock-crossing FIFO
// over- or underflowed, a sample was dropped: it should never happen);
// PL_LED2 is lit while the PLL is locked.
`default_nettype none

module ym_test_top (
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
    wire pix_clk, pix5x_clk, sys_clk, locked, pix_rst, sys_rst;
    ym_test_clk u_clk (.PL_CLK_50M(PL_CLK_50M), .pix_clk(pix_clk), .pix5x_clk(pix5x_clk), .sys_clk(sys_clk),
                       .locked(locked), .pix_rst(pix_rst), .sys_rst(sys_rst));

    wire [29:0] sym;
    wire        played;
    wire [2:0]  fault;
    ym_test_core u_core (
        .sys_clk(sys_clk), .sys_rst(sys_rst), .pix_clk(pix_clk), .pix_rst(pix_rst), .sym(sym),
        .played(played), .played_l(), .played_r(), .fault(fault), .status(),
        .src_valid(), .src_l(), .src_r(), .pc());

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
    reg        phase = 1'b0, faulted = 1'b0;
    always @(posedge pix_clk) begin
        faulted <= faulted | (|fault);
        if (played) begin
            samples <= (samples == 15'd22049) ? 15'd0 : samples + 15'd1;
            if (samples == 15'd22049) phase <= ~phase;
        end
    end
    assign PL_LED1 = ~(phase || faulted);
    assign PL_LED2 = ~locked;
endmodule

`default_nettype wire
