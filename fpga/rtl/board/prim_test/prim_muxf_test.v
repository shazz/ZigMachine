// The wide-function mode of the primitive self-test (rtl/board/prim_test_top.v):
// MUXF7 and MUXF8. The SoC gets them where ABC maps a 7- or 8-input function to
// a LUT7 (two LUT6 + MUXF7) or a LUT8 (four LUT6 + 2 MUXF7 + MUXF8). T7, a
// random 7-input table, is inferred and left to ABC; T8 is INSTANTIATED as four
// LUT6, two MUXF7 and a MUXF8, because ABC maps a lone 8-input table without
// them. Both are looked up by an LFSR index. The reference rotates a copy of each
// table one bit a clock and takes the bit when the count reaches the index.
// One vector each 259 clocks, 256 a run.
`default_nettype none

module prim_muxf_test #(
    parameter [95:0] FLIP = 96'd0
) (
    input  wire         clk,
    input  wire         start,
    input  wire         clear,
    input  wire [31:0]  seed,
    output reg          done,
    output wire [223:0] res
);
    localparam [255:0] T8 = 256'hD23F0824128B2F330C5C7FD0A6A3A4506513270E269E0D37F2A74DE452E6B438;
    localparam [127:0] T7 = 128'h9531985D5D9DC9F81818E811892F902B;
    reg  [8:0]  t = 9'd0;
    reg  [8:0]  k = 9'd0;
    reg         busy = 1'b0;
    initial done = 1'b0;
    reg  [7:0]  idx;
    wire [7:0]  gq;
    prim_lfsr #(.W(8)) gen (.clk(clk), .load(start), .seed(seed), .step(busy && t == 9'd0), .q(gq));

    // --- under test: an 8-input and a 7-input function
    wire [3:0]  l6;
    wire [1:0]  f7;
    wire        f8;
    genvar q;
    generate
        for (q = 0; q < 4; q = q + 1) begin : lut
            LUT6 #(.INIT(T8[q*64 +: 64])) u (
                .I0(idx[0]), .I1(idx[1]), .I2(idx[2]), .I3(idx[3]), .I4(idx[4]), .I5(idx[5]), .O(l6[q])
            );
        end
    endgenerate
    MUXF7 u_f7a (.I0(l6[0]), .I1(l6[1]), .S(idx[6]), .O(f7[0]));
    MUXF7 u_f7b (.I0(l6[2]), .I1(l6[3]), .S(idx[6]), .O(f7[1]));
    MUXF8 u_f8 (.I0(f7[0]), .I1(f7[1]), .S(idx[7]), .O(f8));
    wire [1:0]  got = {f8, T7[idx[6:0]]};

    // --- the reference
    reg  [255:0] r8;
    reg  [127:0] r7;
    reg  [7:0]   j;
    reg  [1:0]   rbit;
    always @(posedge clk)
        if (t == 9'd1) {r8, r7, j} <= {T8, T7, 8'd0};
        else begin
            {r8, r7, j} <= {r8[0], r8[255:1], r7[0], r7[127:1], j + 8'd1};
            if (j == idx) rbit[1] <= r8[0];
            if (j[6:0] == idx[6:0]) rbit[0] <= r7[0];
        end

    // --- the sequence: load, 1 + 256 serial clocks, compare
    always @(posedge clk)
        if (start) {busy, t, k, done} <= {1'b1, 9'd0, 9'd0, 1'b0};
        else if (busy) begin
            if (t == 9'd0) idx <= gq;
            t <= (t == 9'd258) ? 9'd0 : t + 9'd1;
            if (t == 9'd258) {busy, k} <= {k != 9'd255, k + 9'd1};
        end else done <= 1'b1;

    prim_check #(.W(2), .FLIP(FLIP)) chk (
        .clk(clk), .clear(clear), .v(busy && t == 9'd258), .got(got), .exp(rbit), .idx({23'd0, k}), .res(res)
    );
endmodule

`default_nettype wire
