// The fabric half of zm_dvi_out's 10:1 serialiser: a 10-bit TMDS symbol out
// two bits a fast clock, bit 0 first, five fast clocks a symbol. `q[0]` goes to
// an ODDR's D1 (sent on the rising edge, first), `q[1]` to its D2.
//
// `d` is in the pixel clock's domain, from the same PLL as `clk` (5x, edges
// aligned). It is taken every fifth fast clock; any phase of the mod-5 counter
// takes a whole, stable symbol, because `d` changes on a pixel edge and is
// sampled on a fast edge, never between. The counter is free-running from the
// configuration's initial values, so it needs no reset.
//
// Pure fabric, no primitive: tested in CXXRTL with the encoder in front of it
// (tests/tb/zm_tmds_ser_tb.cpp). Proven on the Z7-Lite by `make hdmi-test-oddr`.
`default_nettype none

module zm_tmds_shift (
    input  wire       clk,
    input  wire [9:0] d,
    output wire [1:0] q
);
    reg [2:0] ph = 3'd0;
    reg [9:0] sh = 10'd0;
    always @(posedge clk) begin
        ph <= (ph == 3'd4) ? 3'd0 : ph + 3'd1;
        sh <= (ph == 3'd4) ? d : {2'b00, sh[9:2]};
    end
    assign q = sh[1:0];
endmodule

`default_nettype wire
