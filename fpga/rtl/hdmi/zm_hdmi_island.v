// HDMI data islands (HDMI 1.3a section 5.2.3): when and what. One island a
// line, two packets long, started by the pixel after HSYNC rises:
//   ic  0..7   preamble (control period, CTL0 = CTL2 = 1: zm_hdmi_enc)
//   ic  8..9   leading guard band
//   ic 10..41  packet 0 (`slot` 0), 32 pixels
//   ic 42..73  packet 1 (`slot` 1)
//   ic 74..75  trailing guard band
// At 800x600@60 that is blank pixels 41..116 of 256 (HSYNC rises at blank pixel
// 40); the video preamble and guard (zm_hdmi_enc) take blank pixels 246..255.
//
// A packet is a 24-bit header and four 56-bit subpackets, each followed by its
// BCH ECC (8 bits, G(x) = 1 + x^6 + x^7 + x^8, section 5.2.3.5), sent LSB first:
// the header one bit a pixel on channel 0 bit 2 (32 pixels: 24 data + 8 ECC),
// subpacket i two bits a pixel on channel 1 bit i (even bits) and channel 2 bit
// i (odd bits). Channel 0 bits 0 and 1 carry HSYNC and VSYNC; bit 3 is 0 on the
// first pixel of each packet and 1 on the others. The ECC is computed as the
// bits go out (the CRC-style LFSR below), so a packet needs no precomputation:
// `load` asks the packet source (zm_hdmi_packets) for it the clock before.
// Outputs describe the pixel in this clock: the nibbles to TERC4-encode on
// channels 0..2 for guard bands (channel 0 only) and packets.
`default_nettype none

module zm_hdmi_island (
    input  wire         clk,
    input  wire         rst,
    input  wire         hs,             // the stream entering the TMDS encoders
    input  wire         vs,
    output wire         load,           // take hdr/sub now: they go out from the next clock
    output wire         slot,
    input  wire [23:0]  hdr,
    input  wire [223:0] sub,            // subpacket i at [56 * i +: 56]
    output wire         pre,
    output wire         guard,
    output wire         data,
    output wire [11:0]  nib             // {channel 2, channel 1, channel 0}
);
    function [7:0] ecc(input [7:0] e, input bit_in);
        ecc = (e >> 1) ^ ((e[0] ^ bit_in) ? 8'b10000011 : 8'd0);
    endfunction

    reg  [6:0] ic = 7'd0;
    reg        run = 1'b0, hs_q = 1'b0;
    always @(posedge clk) begin
        hs_q <= hs;
        if (rst) run <= 1'b0;
        else if (!run) {run, ic} <= {hs && !hs_q, 7'd0};
        else {run, ic} <= {ic != 7'd75, ic + 7'd1};
    end
    assign pre = run && (ic < 7'd8);
    assign guard = run && (ic == 7'd8 || ic == 7'd9 || ic == 7'd74 || ic == 7'd75);
    assign data = run && (ic >= 7'd10) && (ic < 7'd74);
    assign load = run && (ic == 7'd9 || ic == 7'd41);
    assign slot = (ic == 7'd41);
    wire [6:0] kk = ic - 7'd10;
    wire [4:0] k = kk[4:0];             // the pixel within its packet
    wire       h_msg = k < 5'd24, s_msg = k < 5'd28;

    reg [23:0]  h_sh = 24'd0;
    reg [7:0]   h_par = 8'd0;
    reg [223:0] s_sh = 224'd0;
    reg [31:0]  s_par = 32'd0;          // subpacket i's ECC at [8 * i +: 8]
    wire [3:0] even, odd;               // subpacket i's two bits this pixel
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : sp
            assign even[i] = s_msg ? s_sh[56 * i] : s_par[8 * i];
            assign odd[i] = s_msg ? s_sh[56 * i + 1] : s_par[8 * i + 1];
            always @(posedge clk) begin
                if (load) begin
                    {s_sh[56 * i +: 56], s_par[8 * i +: 8]} <= {sub[56 * i +: 56], 8'd0};
                end else if (data && s_msg) begin
                    s_par[8 * i +: 8] <= ecc(ecc(s_par[8 * i +: 8], s_sh[56 * i]), s_sh[56 * i + 1]);
                    s_sh[56 * i +: 56] <= s_sh[56 * i +: 56] >> 2;
                end else if (data) begin
                    s_par[8 * i +: 8] <= s_par[8 * i +: 8] >> 2;
                end
            end
        end
    endgenerate

    always @(posedge clk) begin
        if (load) {h_sh, h_par} <= {hdr, 8'd0};
        else if (data && h_msg) {h_sh, h_par} <= {h_sh >> 1, ecc(h_par, h_sh[0])};
        else if (data) h_par <= h_par >> 1;
    end
    wire hbit = h_msg ? h_sh[0] : h_par[0];

    assign nib[3:0] = data ? {k != 5'd0, hbit, vs, hs} : {2'b11, vs, hs};
    assign nib[11:4] = {odd, even};
endmodule

`default_nettype wire
