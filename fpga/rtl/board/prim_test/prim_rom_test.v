// The ROM mode of the primitive self-test (rtl/board/prim_test_top.v): a block
// RAM whose contents come from the bitstream (an `initial` table, as LiteX writes
// its boot ROM), read only. A 2048 x 8 table maps to a RAMB18E1 with port A read
// at 9 bits. The reference recomputes each word from its address in LUTs.
`default_nettype none

module prim_rom_test #(
    parameter [95:0] FLIP = 96'd0
) (
    input  wire         clk,
    input  wire         start,
    input  wire         clear,
    output reg          done,
    output wire [223:0] res
);
    function [7:0] word(input [10:0] a);
        word = a[7:0] ^ {a[2:0], a[10:6]} ^ {a[9:8], a[5:0]} ^ 8'h5A;
    endfunction

    reg [7:0] rom [0:2047];
    integer i;
    initial for (i = 0; i < 2048; i = i + 1) rom[i] = word(i);

    reg        busy = 1'b0, v1 = 1'b0;
    reg [10:0] a, a1;
    reg [7:0]  rd;
    initial done = 1'b0;
    always @(posedge clk) begin
        rd <= rom[a];
        {v1, a1} <= {busy, a};
        if (start) {busy, a, done} <= {1'b1, 11'd0, 1'b0};
        else if (busy) {busy, a} <= {a != 11'd2047, a + 11'd1};
        else if (!v1) done <= 1'b1;
    end
    prim_check #(.W(8), .FLIP(FLIP)) chk (
        .clk(clk), .clear(clear), .v(v1), .got(rd), .exp(word(a1)), .idx({21'd0, a1}), .res(res)
    );
endmodule

`default_nettype wire
