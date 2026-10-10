// One self-test's result (rtl/board/prim_test_top.v): every compare of a word
// read back (got) against the fabric's reference (exp). Kept until `clear`, so a
// looping run accumulates. FLIP inverts reference bits: the break tests use it
// to prove that a wrong word is reported (tests/test_rtl_prim_test.py).
//   res = {checks, bad[95:64], bad[63:32], bad[31:0], first_got, first_idx, errors}
//   bad: the OR of (got ^ exp) over every failed compare, i.e. which bits ever went wrong.
`default_nettype none

module prim_check #(
    parameter integer W = 32,
    parameter [95:0]  FLIP = 96'd0
) (
    input  wire          clk,
    input  wire          clear,
    input  wire          v,
    input  wire [W-1:0]  got,
    input  wire [W-1:0]  exp,
    input  wire [31:0]   idx,
    output wire [223:0]  res
);
    wire [95:0] g = {{(96 - W){1'b0}}, got};
    wire [95:0] e = {{(96 - W){1'b0}}, exp} ^ FLIP;
    wire [95:0] x = g ^ e;
    reg  [31:0] errors, first_idx, first_got, checks;
    reg  [95:0] bad;
    reg         have;

    always @(posedge clk)
        if (clear) begin
            {errors, first_got, checks, bad, have} <= 0;
            first_idx <= 32'hFFFF_FFFF;
        end else if (v) begin
            if (!checks[31]) checks <= checks + 32'd1;  // saturates at 2^31: cheaper than a full compare
            if (x != 96'd0) begin
                if (!errors[31]) errors <= errors + 32'd1;
                if (!have) {have, first_idx, first_got} <= {1'b1, idx, g[31:0]};
                bad <= bad | x;
            end
        end

    assign res = {checks, bad[95:64], bad[63:32], bad[31:0], first_got, first_idx, errors};
endmodule

`default_nettype wire
