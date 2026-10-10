// The carry-chain mode of the primitive self-test (rtl/board/prim_test_top.v):
// a 64-bit add with carry in and out, inferred like any RTL, which maps to a
// CARRY4 chain. The reference is a full adder in plain logic, one bit a clock.
// One vector each 67 clocks, 512 a run.
`default_nettype none

module prim_carry_test #(
    parameter [95:0]  FLIP = 96'd0
) (
    input  wire         clk,
    input  wire         start,
    input  wire         clear,
    input  wire [31:0]  seed,
    output reg          done,
    output wire [223:0] res
);
    reg  [6:0]  t = 7'd0;
    reg  [9:0]  k = 10'd0;
    reg         busy = 1'b0;
    initial done = 1'b0;
    reg  [63:0] hx, hy;
    wire [63:0] gx, gy;
    wire        load = busy && t == 7'd0;
    prim_lfsr #(.W(64)) genx (.clk(clk), .load(start), .seed(seed), .step(load), .q(gx));
    prim_lfsr #(.W(64)) geny (.clk(clk), .load(start), .seed(~seed), .step(load), .q(gy));
    wire        cin = hy[0] ^ hx[63];

    // --- under test
    wire [64:0] sum = {1'b0, hx} + {1'b0, hy} + {64'd0, cin};

    // --- the reference, one bit a clock
    reg  [63:0] sx, sy, rs;
    reg         rc;
    always @(posedge clk)
        if (t == 7'd1) {sx, sy, rc} <= {hx, hy, cin};
        else begin
            rs <= {sx[0] ^ sy[0] ^ rc, rs[63:1]};
            rc <= (sx[0] & sy[0]) | (sx[0] & rc) | (sy[0] & rc);
            {sx, sy} <= {1'b0, sx[63:1], 1'b0, sy[63:1]};
        end

    // --- the sequence: load, 1 + 64 serial clocks, compare
    always @(posedge clk)
        if (start) {busy, t, k, done} <= {1'b1, 7'd0, 10'd0, 1'b0};
        else if (busy) begin
            if (load) {hx, hy} <= {gx, gy};
            t <= (t == 7'd66) ? 7'd0 : t + 7'd1;
            if (t == 7'd66) {busy, k} <= {k != 10'd511, k + 10'd1};
        end else done <= 1'b1;

    prim_check #(.W(65), .FLIP(FLIP)) chk (
        .clk(clk), .clear(clear), .v(busy && t == 7'd66), .got(sum), .exp({rc, rs}), .idx({22'd0, k}), .res(res)
    );
endmodule

`default_nettype wire
