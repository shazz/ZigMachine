// A pulse from one clock domain to another: the source flips a toggle, the
// destination brings it through two flip-flops and pulses on each change.
// Pulses must be at least three destination clocks apart; every user here
// sends at most one a raster line (2,112 pixel clocks).
`default_nettype none

module zm_video_sync (
    input  wire src_clk,
    input  wire src_pulse,
    input  wire dst_clk,
    output wire dst_pulse
);
    reg tog = 1'b0;
    always @(posedge src_clk)
        if (src_pulse) tog <= !tog;

    (* ASYNC_REG = "TRUE" *) reg [1:0] s = 2'b00;
    reg seen = 1'b0;
    always @(posedge dst_clk) begin
        s <= {s[0], tog};
        seen <= s[1];
    end
    assign dst_pulse = s[1] != seen;
endmodule

`default_nettype wire
