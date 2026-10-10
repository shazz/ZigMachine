// I2C master for the HDMI DDC, one operation at a time: START (or repeated
// START), STOP, or a 9-bit transfer. Standard mode, open drain: the pins are only
// ever pulled low or released (the board's 4.7k pull-ups and its 2N7002 level
// shifters to 5 V do the rest, Z7-LITE_R11 sheet "HDMI TX").
//
// A transfer sends `tx` MSB first, a 1 releasing SDA, and samples SDA at every
// bit: a byte write is tx = {byte, 1} (rx[0] is then the sink's ACK, 0 = ACK);
// a byte read is tx = {8'hFF, nack} (rx[8:1] is the byte).
//
// Every operation is four quarters of QUARTER clocks; entering quarter n changes
// the lines as `lines` says. At the end of quarter 1 (SCL released) the master
// waits while SCL reads low: a sink may stretch the clock. SDA is sampled at the
// end of quarter 2, mid-high. QUARTER 200 at 40 MHz is a 50 kHz SCL, which keeps
// every standard-mode minimum (tLOW 4.7 us, tHIGH, tHD;STA, tSU;STO 4.0 us) with
// room to spare: 10 us low, 10 us high, 5 us START/STOP holds.
`default_nettype none

module edid_i2c #(
    parameter integer QUARTER = 200
) (
    input  wire       clk,
    input  wire       rst,             // also aborts: both lines released
    input  wire       go,              // start `cmd` (taken only while idle)
    input  wire [1:0] cmd,             // OP_START, OP_STOP or OP_XFER
    input  wire [8:0] tx,
    output wire       busy,
    output reg  [8:0] rx = 9'd0,
    output reg        scl_low = 1'b0,  // 1: pull SCL low, 0: release it
    output reg        sda_low = 1'b0,
    input  wire       scl_in,          // the pins, asynchronous
    input  wire       sda_in
);
    localparam [1:0] OP_START = 2'd0, OP_STOP = 2'd1, OP_XFER = 2'd2, OP_IDLE = 2'd3;

    reg [1:0] scl_s = 2'b11, sda_s = 2'b11;  // two-flop synchronisers
    always @(posedge clk) {scl_s, sda_s} <= {scl_s[0], scl_in, sda_s[0], sda_in};

    // {scl_low, sda_low} after entering quarter n of operation o (b: the bit to send).
    function [1:0] lines(input [1:0] o, input [1:0] n, input b, input [1:0] cur);
        begin
            lines = cur;
            case (n)
                2'd0: lines[0] = (o == OP_XFER) ? !b : (o == OP_STOP);  // START: SDA up; STOP: SDA down
                2'd1: lines[1] = 1'b0;                                  // SCL released (every op)
                2'd2: if (o != OP_XFER) lines[0] = (o == OP_START);    // the START or STOP edge
                default: if (o != OP_STOP) lines[1] = 1'b1;             // SCL low again
            endcase
        end
    endfunction

    reg [1:0]  op = OP_IDLE;
    reg [1:0]  q = 2'd0;
    reg [3:0]  nbit = 4'd0;
    reg [8:0]  sh = 9'd0;
    localparam [15:0] QM1 = QUARTER - 1;
    reg [15:0] cnt = 16'd0;
    assign busy = op != OP_IDLE;
    wire last_q = (q == 2'd3);
    wire more_bits = (op == OP_XFER) && (nbit != 4'd8);

    always @(posedge clk) begin
        if (rst) begin
            op <= OP_IDLE;
            {scl_low, sda_low} <= 2'b00;
        end else if (op == OP_IDLE) begin
            if (go) begin
                {op, q, nbit, sh, cnt} <= {cmd, 2'd0, 4'd0, tx, QM1};
                {scl_low, sda_low} <= lines(cmd, 2'd0, tx[8], {scl_low, sda_low});
            end
        end else if (cnt != 16'd0) begin
            cnt <= cnt - 16'd1;
        end else if (!(q == 2'd1 && !scl_s[1])) begin  // (else the sink is stretching SCL)
            cnt <= QM1;
            if (q == 2'd2) rx <= {rx[7:0], sda_s[1]};
            if (!last_q) begin
                q <= q + 2'd1;
                {scl_low, sda_low} <= lines(op, q + 2'd1, sh[8], {scl_low, sda_low});
            end else if (more_bits) begin
                {q, nbit, sh} <= {2'd0, nbit + 4'd1, sh[7:0], 1'b1};
                {scl_low, sda_low} <= lines(op, 2'd0, sh[7], {scl_low, sda_low});
            end else begin
                op <= OP_IDLE;
            end
        end
    end
endmodule

`default_nettype wire
