// One TMDS channel encoder, DVI 1.0 section 3.3.3: 8 data bits (or 2 control
// bits in blanking) to a 10-bit symbol, bit 0 sent first.
//   1. Transition minimising: q_m chains the data bits by XOR, or by XNOR when
//      that gives fewer transitions (more than four ones, or four with d[0] 0);
//      q_m[8] records which.
//   2. DC balance: `cnt` is the running disparity (ones minus zeros) of what
//      was sent since the last blanking. Each word is sent as q_m or inverted
//      (q[9] says which), whichever pulls `cnt` back toward 0.
// In blanking the four control tokens are sent and `cnt` restarts at 0.
// Two registered stages: a symbol leaves two clocks after its data enters.
`default_nettype none

module zm_tmds_enc (
    input  wire       clk,
    input  wire       rst,
    input  wire       de,
    input  wire [7:0] d,
    input  wire [1:0] c,        // {C1, C0}: on channel 0, {VSYNC, HSYNC}
    output reg  [9:0] q
);
    // Stage 1: transition minimising.
    wire [3:0] n1d = d[0] + d[1] + d[2] + d[3] + d[4] + d[5] + d[6] + d[7];
    wire xnor_ = n1d > 4'd4 || (n1d == 4'd4 && !d[0]);
    wire [7:0] qm;
    assign qm[0] = d[0];
    genvar i;
    generate
        for (i = 1; i < 8; i = i + 1) begin : chain
            assign qm[i] = xnor_ ? !(qm[i - 1] ^ d[i]) : qm[i - 1] ^ d[i];
        end
    endgenerate

    reg [8:0] m;
    reg       de1;
    reg [1:0] c1;
    always @(posedge clk) {m, de1, c1} <= {!xnor_, qm, de, c};

    // Stage 2: DC balance. Disparities are even: ones - zeros of 8 bits.
    wire [3:0] n1 = m[0] + m[1] + m[2] + m[3] + m[4] + m[5] + m[6] + m[7];
    wire signed [5:0] diff = $signed({2'b0, n1}) * 2 - 6'sd8;   // N1 - N0
    reg  signed [5:0] cnt = 6'sd0;
    wire balanced = cnt == 0 || diff == 0;
    wire invert = balanced ? !m[8] : (cnt > 0) == (diff > 0);
    wire signed [5:0] adj = balanced ? 6'sd0 : invert ? (m[8] ? 6'sd2 : 6'sd0) : (m[8] ? 6'sd0 : -6'sd2);
    always @(posedge clk) begin
        if (rst) begin
            cnt <= 6'sd0;
            q <= 10'b1101010100;
        end else if (!de1) begin
            cnt <= 6'sd0;
            case (c1)
                2'b00: q <= 10'b1101010100;
                2'b01: q <= 10'b0010101011;
                2'b10: q <= 10'b0101010100;
                default: q <= 10'b1010101011;
            endcase
        end else begin
            q <= {invert, m[8], invert ? ~m[7:0] : m[7:0]};
            cnt <= cnt + adj + (invert ? -diff : diff);
        end
    end
endmodule

`default_nettype wire
