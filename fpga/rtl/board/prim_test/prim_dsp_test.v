// One DSP48E1 configuration of the primitive self-test (rtl/board/prim_test_top.v).
// The multiply is INFERRED, and MODE places the registers around it the way
// the SoC's RTL does, so Yosys's xilinx_dsp packs the same configurations
// (tools/prim_allowlist.py names them by OPMODE and the registers used):
//   0  m <= a*b                    M          5  a*b                  (none)
//   1  ra, rb <= a, b; m <= ra*rb  A B M      6  ra <= a; c + ra*b     A, OPMODE C+M
//   2  m <= a*b; p <= m            M P        7  ra <= a; m <= ra*b    A M
//   3  m <= a*b; c + m             M, C+M     8  rb <= b; m <= a*rb    B M
//   4  p <= (first ? 0 : p) + a*b  the multiply-accumulate (P feedback)
//   9  c + a*b                     (none), C+M
//  10  rc <= c; rc + a*b           C, C+M
// One 16 x 16 vector each 20 clocks, 1024 a run. The reference multiplies by
// shift-and-add in the fabric, 16 clocks, and accumulates the same way for 4.
// Each lane has its own LFSR (seeded with MODE), so no two lanes compute the
// same product and Yosys cannot merge two configurations into one.
`default_nettype none

module prim_dsp_test #(
    parameter integer MODE = 0,
    parameter [95:0]  FLIP = 96'd0
) (
    input  wire         clk,
    input  wire         start,
    input  wire         clear,
    input  wire [31:0]  seed,
    output reg          done,
    output wire [223:0] res
);
    reg  [4:0]  t = 5'd0;
    reg  [10:0] k = 11'd0;          // vectors this run
    reg         busy = 1'b0;
    initial done = 1'b0;
    reg  [15:0] hx, hy;
    reg  [31:0] hz;
    wire [63:0] gq;
    prim_lfsr #(.W(64)) gen (.clk(clk), .load(start), .seed(seed ^ MODE), .step(busy && t == 5'd0), .q(gq));
    wire [15:0] a = hx ^ {16{hz[31]}};
    wire [15:0] b = hy ^ {16{hz[30]}};
    wire [31:0] c = hz ^ {hy, hx};
    wire        first = k[1:0] == 2'd0;
    wire        acc_en = busy && t == 5'd1;

    // --- the configuration under test
    reg  [15:0] ra, rb;
    reg  [31:0] rc, m;
    reg  [33:0] p;
    wire [33:0] got;
    generate
        case (MODE)
            0: begin : m0 always @(posedge clk) m <= a * b; assign got = m; end
            1: begin : m1 always @(posedge clk) begin ra <= a; rb <= b; m <= ra * rb; end assign got = m; end
            2: begin : m2 always @(posedge clk) begin m <= a * b; p <= m; end assign got = p; end
            3: begin : m3 always @(posedge clk) m <= a * b; assign got = c + m; end
            4: begin : m4 always @(posedge clk) if (acc_en) p <= (first ? 34'd0 : p) + a * b; assign got = p; end
            5: begin : m5 assign got = a * b; end
            6: begin : m6 always @(posedge clk) ra <= a; assign got = c + ra * b; end
            7: begin : m7 always @(posedge clk) begin ra <= a; m <= ra * b; end assign got = m; end
            8: begin : m8 always @(posedge clk) begin rb <= b; m <= a * rb; end assign got = m; end
            9: begin : m9 assign got = c + a * b; end
            default: begin : m10 always @(posedge clk) rc <= c; assign got = rc + a * b; end
        endcase
    endgenerate

    // --- the reference: shift-and-add, then + c, or accumulated over 4 vectors
    reg  [31:0] ma, acc;
    reg  [15:0] mb;
    reg  [33:0] racc;
    always @(posedge clk)
        if (t == 5'd1) {ma, mb, acc} <= {16'd0, a, b, 32'd0};
        else begin
            if (mb[0]) acc <= acc + ma;
            {ma, mb} <= {ma[30:0], 1'b0, 1'b0, mb[15:1]};
            if (t == 5'd18) racc <= (first ? 34'd0 : racc) + {2'b00, acc};
        end
    wire        is_c = MODE == 3 || MODE == 6 || MODE == 9 || MODE == 10;
    wire [33:0] exp = MODE == 4 ? racc : is_c ? {2'b00, c} + {2'b00, acc} : {2'b00, acc};

    // --- the sequence: 20 clocks a vector
    always @(posedge clk)
        if (start) {busy, t, k, done} <= {1'b1, 5'd0, 11'd0, 1'b0};
        else if (busy) begin
            if (t == 5'd0) {hx, hy, hz} <= gq;
            t <= (t == 5'd19) ? 5'd0 : t + 5'd1;
            if (t == 5'd19) {busy, k} <= {k != 11'd1023, k + 11'd1};
        end else done <= 1'b1;

    prim_check #(.W(34), .FLIP(FLIP)) chk (
        .clk(clk), .clear(clear), .v(busy && t == 5'd19), .got(got), .exp(exp), .idx({21'd0, k}), .res(res)
    );
endmodule

`default_nettype wire
