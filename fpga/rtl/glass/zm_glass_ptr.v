// The glass's mouse: REG_POINTER (fpga/glass/src/map.zig, PTR_*), the state
// demo.pointer(x, y, buttons) is called with. A state, not a queue: the
// browser calls pointer() with the latest position on every move, so only the
// newest matters and motion never crowds keys out of the key FIFO.
//
// The ARM writes x, y and the buttons held. A click can be shorter than the
// firmware's poll, so every button pressed since the firmware's last ack stays
// visible (the browser defers a release by a frame for the same reason). SEQ
// counts changes, so the firmware polls one word. The firmware acks the SEQ it
// delivered: a stale ack (the ARM wrote since) is ignored, and an ack that
// drops a latched button the ARM no longer holds bumps SEQ, so that release
// is delivered on the next poll. An ARM write in the ack's cycle wins.
`default_nettype none

module zm_glass_ptr (
    input  wire        clk,
    input  wire        rst,
    input  wire        we,        // the ARM writes REG_POINTER
    input  wire [23:0] wdata,     // {buttons[3:0], y[9:0], x[9:0]}
    input  wire        ack,       // the firmware delivered...
    input  wire [7:0]  ack_seq,   // ...this SEQ
    output wire [31:0] ptr        // {seq, held | latched buttons, y, x}
);
    reg [23:0] cur;               // as the ARM last wrote it
    reg [3:0]  latch;             // pressed since the last good ack
    reg [7:0]  seq;
    wire [3:0] held = cur[23:20];
    assign ptr = {seq, held | latch, cur[19:0]};

    always @(posedge clk) begin
        if (rst) begin
            {cur, latch, seq} <= 36'd0;
        end else if (we) begin
            cur <= wdata;
            latch <= latch | wdata[23:20];
            seq <= seq + 8'd1;
        end else if (ack && ack_seq == seq) begin
            latch <= 4'd0;
            if ((latch & ~held) != 4'd0) seq <= seq + 8'd1;
        end
    end
endmodule

`default_nettype wire
