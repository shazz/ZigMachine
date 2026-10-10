// The shift-register (SRL16E / SRLC32E) mode of the primitive self-test
// (rtl/board/prim_test_top.v): DW parallel N-deep delay lines with a clock
// enable and no reset, inferred, which Yosys maps to one SRL per bit. The
// enable follows a pseudo-random bit, so CE is tested too. The reference is a
// second LFSR that starts stepping N enabled clocks after the one feeding the
// line: the word leaving the line must be that LFSR's.
`default_nettype none

module prim_srl_test #(
    parameter integer N = 16,
    parameter integer DW = 8,
    parameter [95:0]  FLIP = 96'd0
) (
    input  wire         clk,
    input  wire         start,
    input  wire         clear,
    input  wire [31:0]  seed,
    output reg          done,
    output wire [223:0] res
);
    localparam [12:0] N13 = N;
    reg  [12:0]   n = 13'd0;       // enabled shifts this run; the run is 4096 of them
    reg           busy = 1'b0;
    initial done = 1'b0;
    wire [DW-1:0] din, ref_q;
    wire [7:0]    ce_src;
    wire          en = busy && ce_src[3];
    prim_lfsr #(.W(DW)) gen (.clk(clk), .load(start), .seed(seed), .step(en), .q(din));
    prim_lfsr #(.W(DW)) refl (.clk(clk), .load(start), .seed(seed), .step(en && n >= N), .q(ref_q));
    prim_lfsr #(.W(8)) ce (.clk(clk), .load(start), .seed(~seed), .step(busy), .q(ce_src));

    reg [DW-1:0] sr [0:N-1];
    integer i;
    always @(posedge clk)
        if (en) begin
            sr[0] <= din;
            for (i = 1; i < N; i = i + 1) sr[i] <= sr[i - 1];
        end

    always @(posedge clk)
        if (start) {busy, n, done} <= {1'b1, 13'd0, 1'b0};
        else if (busy) begin
            if (en) n <= n + 13'd1;
            if (en && n == 13'd4095) busy <= 1'b0;
        end else done <= 1'b1;

    prim_check #(.W(DW), .FLIP(FLIP)) chk (
        .clk(clk), .clear(clear), .v(busy && n >= N), .got(sr[N-1]), .exp(ref_q), .idx({19'd0, n - N13}), .res(res)
    );
endmodule

`default_nettype wire
