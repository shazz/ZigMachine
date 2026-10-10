// What the HDMI data islands carry (HDMI 1.3a section 5.3, CEA-861-D section 6),
// one island a line (zm_hdmi_island), two packets an island:
//   slot 0: an Audio Sample packet with the samples queued since the last one
//           (one or two a line at 48 kHz on 800x600@60's 37.9 kHz lines; four
//           at most), or a null packet when none is queued;
//   slot 1: the AVI InfoFrame on the frame's first island, the Audio InfoFrame
//           on its second, otherwise Audio Clock Regeneration (N, CTS) once for
//           each CTS zm_hdmi_acr measures (every N / 128 samples: about every
//           1.1 ms at 44.1 kHz, 1 ms at 48 kHz), null packets otherwise.
// Samples: 2-channel L-PCM in IEC 60958 frames, 16 bits left-justified in the
// 24-bit word, V = U = 0, P = even parity over the word, V, U and C, C = the
// channel status bit of the frame (IEC 60958-3 consumer: copyright not asserted,
// channel 1 left / 2 right, the sample rate, 16-bit word), B on frame 0 of 192.
// The rate's four bits are channel status bits 24..27 (IEC 60958-3): 0000 for
// 44.1 kHz, 0100 (bit 25) for 48 kHz: CS_48K.
// AVI: RGB, 4:3, IT content, full-range RGB, no VIC (800x600 is not a CEA-861
// format). Audio InfoFrame: 2 channels, coding and rate "refer to stream header".
`default_nettype none

module zm_hdmi_packets #(
    parameter [19:0] ACR_N = 20'd6144,     // 6144 for 48 kHz, 6272 for 44.1 kHz
    parameter        CS_48K = 1'b1         // the channel status rate: 48 kHz, else 44.1
) (
    input  wire         clk,
    input  wire         rst,
    input  wire         vs,
    input  wire [19:0]  acr_cts,           // zm_hdmi_acr: the last period's CTS
    input  wire         acr_new,           // ... just measured: send it once
    input  wire         load,              // zm_hdmi_island takes a packet now
    input  wire         slot,
    output reg  [23:0]  hdr,
    output reg  [223:0] sub,
    input  wire         aud_valid,         // a stereo sample, this clock's domain
    input  wire [15:0]  aud_l,
    input  wire [15:0]  aud_r,
    output reg          aud_overflow = 1'b0
);
    localparam [7:0] AVI_PB1 = 8'h00, AVI_PB2 = 8'h18, AVI_PB3 = 8'h88, AVI_PB4 = 8'h00;
    localparam [7:0] AVI_CS = 8'h00 - (8'h82 + 8'h02 + 8'h0D + AVI_PB1 + AVI_PB2 + AVI_PB3 + AVI_PB4);
    localparam [7:0] AIF_PB1 = 8'h01;      // CT 0, CC 1: two channels
    localparam [7:0] AIF_CS = 8'h00 - (8'h84 + 8'h01 + 8'h0A + AIF_PB1);
    wire [55:0] acr_sub = {ACR_N[7:0], ACR_N[15:8], 4'h0, ACR_N[19:16],
                           acr_cts[7:0], acr_cts[15:8], 4'h0, acr_cts[19:16], 8'h00};

    // --- the sample queue and the IEC 60958 frame count
    reg [31:0] q [0:3];                    // {left, right}
    reg [2:0]  n = 3'd0;
    reg [7:0]  fc = 8'd0;                  // the next sample's frame, 0..191
    wire       take = load && !slot;
    always @(posedge clk) begin
        if (rst) begin
            {n, fc} <= {3'd0, 8'd0};
        end else begin
            if (take) fc <= (fc + n >= 8'd192) ? fc + n - 8'd192 : fc + n;
            if (aud_valid && !take && n == 3'd4) aud_overflow <= 1'b1;
            if (aud_valid && (take || n != 3'd4)) q[take ? 3'd0 : n] <= {aud_l, aud_r};
            if (take) n <= {2'd0, aud_valid};
            else if (aud_valid && n != 3'd4) n <= n + 3'd1;
        end
    end

    // --- the frame of the island: which line, for slot 1
    reg [9:0] line = 10'd0;
    reg       vs_q = 1'b0;
    reg       acr_due = 1'b0;               // a CTS measured and not yet sent
    wire      acr_now = slot && line > 10'd1 && acr_due;
    always @(posedge clk) begin
        vs_q <= vs;
        if (vs && !vs_q) line <= 10'd0;
        else if (load && slot) line <= line + 10'd1;
        // A packet loaded with a CTS that has just changed carries the new one.
        if (rst || (load && acr_now)) acr_due <= 1'b0;
        else if (acr_new) acr_due <= 1'b1;
    end

    // Channel status bit `f` (0..191), left or right (IEC 60958-3).
    function cs(input [7:0] f, input right);
        cs = (f == 8'd2) || (CS_48K && f == 8'd25) || (f == 8'd33) || (f == (right ? 8'd21 : 8'd20));
    endfunction

    // --- the Audio Sample packet's subpackets and B flags
    wire [3:0]   present = (n == 3'd0) ? 4'b0000 : (n == 3'd1) ? 4'b0001 : (n == 3'd2) ? 4'b0011
                         : (n == 3'd3) ? 4'b0111 : 4'b1111;
    wire [3:0]   b_flag;
    wire [223:0] asp;
    genvar j;
    generate
        for (j = 0; j < 4; j = j + 1) begin : smp
            wire [8:0]  fj0 = fc + j;
            wire [7:0]  fj = (fj0 >= 9'd192) ? fj0 - 9'd192 : fj0[7:0];
            wire [23:0] l24 = {q[j][31:16], 8'h00}, r24 = {q[j][15:0], 8'h00};
            wire        cl = cs(fj, 1'b0), cr = cs(fj, 1'b1);
            assign b_flag[j] = present[j] && fj == 8'd0;
            assign asp[56 * j +: 56] = present[j] ? {^{r24, cr}, cr, 2'b00, ^{l24, cl}, cl, 2'b00, r24, l24} : 56'd0;
        end
    endgenerate

    always @(*) begin
        {hdr, sub} = {24'd0, 224'd0};                                    // null packet
        if (!slot && n != 3'd0) begin
            {hdr, sub} = {b_flag, 4'h0, 4'h0, present, 8'h02, asp};      // Audio Sample
        end else if (slot && line == 10'd0) begin
            hdr = {8'd13, 8'h02, 8'h82};                                 // AVI InfoFrame v2
            sub[55:0] = {16'h0000, AVI_PB4, AVI_PB3, AVI_PB2, AVI_PB1, AVI_CS};
        end else if (slot && line == 10'd1) begin
            hdr = {8'd10, 8'h01, 8'h84};                                 // Audio InfoFrame v1
            sub[55:0] = {40'h0, AIF_PB1, AIF_CS};
        end else if (acr_now) begin
            {hdr, sub} = {24'h000001, acr_sub, acr_sub, acr_sub, acr_sub}; // Audio Clock Regeneration
        end
    end
endmodule

`default_nettype wire
