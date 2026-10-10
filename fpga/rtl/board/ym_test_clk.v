// The ym-test bitstream's clocks: one PLLE2 off PL_CLK_50M, VCO 50 x 20 = 1000 MHz:
// /25 = 40 MHz pixel clock, /5 = 200 MHz for the ODDR serialisers, /20 = 50 MHz
// system clock for the audio core (as rtl/board/hdmi_clk.v, plus the system
// clock: the three come from one VCO, so 44.1 kHz is the same exact fraction of
// both domains). Each domain's reset is held until the PLL locks and released
// synchronously to its own clock.
`default_nettype none

module ym_test_clk (
    input  wire PL_CLK_50M,
    output wire pix_clk,
    output wire pix5x_clk,
    output wire sys_clk,
    output wire locked,
    output wire pix_rst,
    output wire sys_rst
);
    wire fb, pix_pll, pix5x_pll, sys_pll;
    PLLE2_ADV #(
        .CLKIN1_PERIOD(20.0), .DIVCLK_DIVIDE(1), .CLKFBOUT_MULT(20),
        .CLKOUT0_DIVIDE(25), .CLKOUT0_PHASE(0.0),
        .CLKOUT1_DIVIDE(5), .CLKOUT1_PHASE(0.0),
        .CLKOUT2_DIVIDE(20), .CLKOUT2_PHASE(0.0),
        .REF_JITTER1(0.01), .STARTUP_WAIT("FALSE")
    ) u_pll (
        .CLKIN1(PL_CLK_50M), .CLKFBIN(fb), .CLKFBOUT(fb), .RST(1'b0), .PWRDWN(1'b0),
        .CLKOUT0(pix_pll), .CLKOUT1(pix5x_pll), .CLKOUT2(sys_pll), .LOCKED(locked)
    );
    BUFG u_bufg_pix (.I(pix_pll), .O(pix_clk));
    BUFG u_bufg_pix5x (.I(pix5x_pll), .O(pix5x_clk));
    BUFG u_bufg_sys (.I(sys_pll), .O(sys_clk));

    reg [1:0] pix_sync = 2'b11, sys_sync = 2'b11;
    always @(posedge pix_clk or negedge locked) begin
        if (!locked) pix_sync <= 2'b11;
        else pix_sync <= {pix_sync[0], 1'b0};
    end
    always @(posedge sys_clk or negedge locked) begin
        if (!locked) sys_sync <= 2'b11;
        else sys_sync <= {sys_sync[0], 1'b0};
    end
    assign pix_rst = pix_sync[1];
    assign sys_rst = sys_sync[1];
endmodule

`default_nettype wire
