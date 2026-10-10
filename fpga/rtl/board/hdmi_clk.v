// The HDMI bring-up clocks, shared by the EDID and HDMI-audio test tops (the
// same PLL settings as rtl/board/hdmi_test_top.v and the board SoC): one PLLE2
// off PL_CLK_50M, VCO 50 x 20 = 1000 MHz, /25 = 40 MHz pixel clock, /5 = 200 MHz
// for the ODDR serialisers, both through a BUFG. `rst` (pixel domain) is held
// until the PLL locks and released synchronously.
`default_nettype none

module hdmi_clk (
    input  wire PL_CLK_50M,
    output wire pix_clk,
    output wire pix5x_clk,
    output wire locked,
    output wire rst
);
    wire fb, pix_pll, pix5x_pll;
    PLLE2_ADV #(
        .CLKIN1_PERIOD(20.0), .DIVCLK_DIVIDE(1), .CLKFBOUT_MULT(20),
        .CLKOUT0_DIVIDE(25), .CLKOUT0_PHASE(0.0),
        .CLKOUT1_DIVIDE(5), .CLKOUT1_PHASE(0.0),
        .REF_JITTER1(0.01), .STARTUP_WAIT("FALSE")
    ) u_pll (
        .CLKIN1(PL_CLK_50M), .CLKFBIN(fb), .CLKFBOUT(fb), .RST(1'b0), .PWRDWN(1'b0),
        .CLKOUT0(pix_pll), .CLKOUT1(pix5x_pll), .LOCKED(locked)
    );
    BUFG u_bufg_pix (.I(pix_pll), .O(pix_clk));
    BUFG u_bufg_pix5x (.I(pix5x_pll), .O(pix5x_clk));

    reg [1:0] rst_sync = 2'b11;
    always @(posedge pix_clk or negedge locked) begin
        if (!locked) rst_sync <= 2'b11;
        else rst_sync <= {rst_sync[0], 1'b0};
    end
    assign rst = rst_sync[1];
endmodule

`default_nettype wire
