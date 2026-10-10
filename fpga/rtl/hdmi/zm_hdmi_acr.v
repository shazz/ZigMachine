// The audio sample clock and the Audio Clock Regeneration values (HDMI 1.3a
// section 7.2), both from ONE fractional accumulator on the TMDS (pixel) clock:
//   - `strobe` pulses at fs = f_pix x INC / MOD on average (44.1 kHz at 40 MHz:
//     INC 441, MOD 400000; 48 kHz: 3 / 2500), never two clocks running;
//   - every SPC = N / 128 strobes (49 at 44.1 kHz, N 6272; 48 at 48 kHz, N 6144)
//     `cts` takes the number of pixel clocks those SPC samples took and
//     `cts_new` pulses: that is the CTS of the period, measured as a real source
//     measures it. At 44.1 kHz it is 44444 or 44445 (400000 / 9 on average:
//     four 44445s in every nine), at 48 kHz always 40000.
// The sink regenerates 128 fs = f_pix x N / CTS. Because the CTS values are
// counted from the same strobes that release the samples, the sum of the CTS
// sent equals the clocks elapsed, exactly: the sink's average rate and the
// source's sample rate cannot drift apart (zm_hdmi_packets sends every CTS once).
`default_nettype none

module zm_hdmi_acr #(
    parameter integer INC = 441,
    parameter integer MOD = 400000,
    parameter integer SPC = 49
) (
    input  wire        clk,
    input  wire        rst,
    output reg         strobe = 1'b0,
    output reg  [19:0] cts = 20'd0,
    output reg         cts_new = 1'b0
);
    reg  [19:0] acc = 20'd0;
    reg  [19:0] clocks = 20'd0;          // pixel clocks since the period began
    reg  [7:0]  samples = 8'd0;          // strobes in this period
    wire [20:0] acc_inc = {1'b0, acc} + INC;
    wire        hit = acc_inc >= MOD;
    wire        last = hit && samples == SPC - 1;

    always @(posedge clk) begin
        if (rst) begin
            {acc, clocks, samples, strobe, cts_new} <= 0;
        end else begin
            acc <= hit ? acc_inc - MOD : acc_inc[19:0];
            strobe <= hit;
            cts_new <= last;
            clocks <= last ? 20'd0 : clocks + 20'd1;
            if (last) cts <= clocks + 20'd1;
            if (hit) samples <= last ? 8'd0 : samples + 8'd1;
        end
    end
endmodule

`default_nettype wire
