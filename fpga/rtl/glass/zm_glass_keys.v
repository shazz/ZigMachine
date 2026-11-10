// The glass's key FIFO (zm_glass_regs.v): KEY_DEPTH events pushed by the ARM (REG_KEY_PUSH),
// popped by the cart CPU. A push into a full FIFO is dropped and sets `overflow` (sticky);
// `flush` (CTRL_KEY_FLUSH) empties it and clears `overflow`.
`default_nettype none

module zm_glass_keys #(
    parameter integer KD = 16
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        flush,
    input  wire        push,
    input  wire [31:0] wdata,
    input  wire        pop_req,
    output wire        key_valid,
    output wire [31:0] key_data,   // the oldest event, while key_valid
    output reg  [4:0]  level,
    output wire        full,
    output reg         overflow
);
    reg [31:0] fifo [0:KD - 1];
    reg [3:0]  rd, wr;
    assign key_valid = level != 5'd0;
    assign key_data = fifo[rd];
    assign full = level == KD[4:0];
    wire pop = pop_req && key_valid;

    always @(posedge clk) begin
        if (rst || flush) begin
            {rd, wr, level, overflow} <= 14'd0;
        end else begin
            if (push && !full) begin
                fifo[wr] <= wdata;
                wr <= wr + 4'd1;
            end
            if (push && full) overflow <= 1'b1;
            if (pop) rd <= rd + 4'd1;
            level <= level + {4'd0, push && !full} - {4'd0, pop};
        end
    end
endmodule

`default_nettype wire
