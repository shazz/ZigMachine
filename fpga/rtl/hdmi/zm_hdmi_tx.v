// HDMI out with audio: the video of a DVI source (RGB, DE, HSYNC, VSYNC, as
// zm_dvi_out takes them) plus stereo samples, to three TMDS symbol
// streams for the serialisers (the clock channel is the caller's: 0000011111).
// HDMI 1.3a section 5.2: every video line is preceded by an 8-pixel preamble
// and a 2-pixel guard band, and every line's horizontal blank carries one data
// island (zm_hdmi_island) of two packets (zm_hdmi_packets): audio samples,
// InfoFrames, clock regeneration. Only for an HDMI sink (its EDID has the HDMI
// VSDB: tools/edid_decode.py); a DVI-only monitor wants zm_dvi_out.
//
// The video is delayed by 10 clocks so the encoder knows when DE will rise
// before it does: the preamble and guard band take the 10 pixels before it, out
// of the blank. Requirements on the timing: every horizontal blank at least
// 10 + 76 + 4 pixels, HSYNC rising at least 4 pixels after DE falls and its
// island (76 pixels) ending at least 14 before DE rises again. 800x600@60
// (zm_vtiming) has 40 pixels before HSYNC and 129 after its island.
// Latency: 12 clocks from (rgb, de, syncs) to `sym`.
//
// The sample rate is this clock x RATE_INC / RATE_MOD (zm_hdmi_acr): `aud_req`
// pulses once a sample period, and the source answers with `aud_valid` (any
// clock before the next request). The defaults are 48 kHz at a 40 MHz pixel
// clock; 44.1 kHz is RATE_INC 441, RATE_MOD 400000, ACR_N 6272, CS_48K 0. The
// CTS sent is measured from the same strobes (44444 / 44445 at 44.1 kHz).
`default_nettype none

module zm_hdmi_tx #(
    parameter integer RATE_INC = 3,
    parameter integer RATE_MOD = 2500,
    parameter [19:0]  ACR_N = 20'd6144,
    parameter         CS_48K = 1'b1
) (
    input  wire        clk,             // pixel clock
    input  wire        rst,
    input  wire [7:0]  r, g, b,
    input  wire        de, hsync, vsync,
    output wire        aud_req,         // a sample is due: answer with aud_valid
    input  wire        aud_valid,
    input  wire [15:0] aud_l,
    input  wire [15:0] aud_r,
    output wire [29:0] sym,             // {channel 2, channel 1, channel 0}, bit 0 first
    output wire        aud_overflow     // sticky: a sample was dropped (should never be)
);
    // The 10-clock delay; dl[9] enters the encoders, dl[9 - k] is k pixels ahead of it.
    reg [26:0] dl [0:9];
    integer i;
    always @(posedge clk) begin
        dl[0] <= {r, g, b, de, hsync, vsync};
        for (i = 1; i < 10; i = i + 1) dl[i] <= dl[i - 1];
    end
    wire [7:0] dr = dl[9][26:19], dg = dl[9][18:11], db = dl[9][10:3];
    wire       dde = dl[9][2], dhs = dl[9][1], dvs = dl[9][0];
    wire       de_in2 = dl[8][2] || dl[7][2];           // video 1 or 2 pixels ahead
    wire       de_in10 = de || dl[0][2] || dl[1][2] || dl[2][2] || dl[3][2] || dl[4][2] || dl[5][2] || dl[6][2];
    wire       vguard = !dde && de_in2;
    wire       vpre = !dde && !de_in2 && de_in10;

    wire         load, slot, dpre, dguard, ddata;
    wire [23:0]  hdr;
    wire [223:0] sub;
    wire [11:0]  nib;
    zm_hdmi_island u_island (
        .clk(clk), .rst(rst), .hs(dhs), .vs(dvs), .load(load), .slot(slot), .hdr(hdr), .sub(sub),
        .pre(dpre), .guard(dguard), .data(ddata), .nib(nib));
    wire [19:0] cts;
    wire        cts_new;
    zm_hdmi_acr #(.INC(RATE_INC), .MOD(RATE_MOD), .SPC(ACR_N / 128)) u_acr (
        .clk(clk), .rst(rst), .strobe(aud_req), .cts(cts), .cts_new(cts_new));
    zm_hdmi_packets #(.ACR_N(ACR_N), .CS_48K(CS_48K)) u_packets (
        .clk(clk), .rst(rst), .vs(dvs), .acr_cts(cts), .acr_new(cts_new), .load(load), .slot(slot), .hdr(hdr), .sub(sub),
        .aud_valid(aud_valid), .aud_l(aud_l), .aud_r(aud_r), .aud_overflow(aud_overflow));
    zm_hdmi_enc u_enc (
        .clk(clk), .rst(rst), .r(dr), .g(dg), .b(db), .de(dde), .hs(dhs), .vs(dvs),
        .vpre(vpre), .dpre(dpre), .vguard(vguard), .dguard(dguard), .ddata(ddata), .nib(nib), .sym(sym));
endmodule

`default_nettype wire
