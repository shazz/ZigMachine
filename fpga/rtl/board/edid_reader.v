// Reads the sink's EDID over the DDC (rtl/board/edid_i2c.v): the base block and
// the first extension (normally the CEA-861 one), 256 bytes from the EEPROM at
// I2C address 0x50, again every 2^PERIOD_BITS clocks (0.42 s at 40 MHz) so a
// monitor plugged in later is read too. One attempt, each step one I2C operation:
//   bus recovery (nine clocks with SDA released, then STOP: frees a sink left
//   mid-byte), START, 0xA0, offset 0, repeated START, 0xA1, 256 reads (ACK each,
//   NACK the last), STOP.
// `status` is the result of the last finished attempt (ST_*): OK, a NAK on one
// of the three header bytes, or TIMEOUT (an attempt not done by the next period,
// e.g. SCL held low). `reads` counts good attempts. The bytes land in `edid`
// as they arrive, and `rowsum` keeps each 8-byte row's sum mod 256 (for the
// screen, so a transcription can be checked a row at a time). Both are read
// through registered ports, one clock of latency.
`default_nettype none

module edid_reader #(
    parameter integer QUARTER = 200,
    parameter integer PERIOD_BITS = 24
) (
    input  wire       clk,
    input  wire       rst,
    output wire       scl_low,
    output wire       sda_low,
    input  wire       scl_in,
    input  wire       sda_in,
    output reg  [2:0] status = 3'd0,
    output reg  [7:0] reads = 8'd0,
    input  wire [7:0] rd_addr,
    output reg  [7:0] rd_data = 8'd0,
    input  wire [4:0] sum_addr,
    output reg  [7:0] sum_data = 8'd0
);
    localparam [2:0] ST_NONE = 3'd0, ST_OK = 3'd1, ST_NAK_AW = 3'd2, ST_NAK_OFF = 3'd3, ST_NAK_AR = 3'd4,
                     ST_TIMEOUT = 3'd5;
    localparam [3:0] S_WAIT = 4'd0, S_RECOVER = 4'd1, S_STOP0 = 4'd2, S_START = 4'd3, S_AW = 4'd4, S_OFF = 4'd5,
                     S_RSTART = 4'd6, S_AR = 4'd7, S_READ = 4'd8, S_STOP = 4'd9;
    localparam [1:0] OP_START = 2'd0, OP_STOP = 2'd1, OP_XFER = 2'd2;

    reg [7:0] edid [0:255];
    reg [7:0] rowsum [0:31];
    always @(posedge clk) {rd_data, sum_data} <= {edid[rd_addr], rowsum[sum_addr]};

    reg [3:0] step = S_WAIT;
    reg [7:0] n = 8'd0;               // the byte being read
    reg [7:0] acc = 8'd0;             // this row's running sum
    reg [2:0] err = ST_OK;            // this attempt's result so far
    reg       go = 1'b0, issued = 1'b0, abort = 1'b0;
    reg [PERIOD_BITS-1:0] timer = 0;
    wire      tick = &timer;

    // The operation each step issues.
    reg [1:0] cmd;
    reg [8:0] tx;
    always @(*) begin
        case (step)
            S_STOP0, S_STOP: {cmd, tx} = {OP_STOP, 9'h1FF};
            S_START, S_RSTART: {cmd, tx} = {OP_START, 9'h1FF};
            S_AW: {cmd, tx} = {OP_XFER, 8'hA0, 1'b1};
            S_OFF: {cmd, tx} = {OP_XFER, 8'h00, 1'b1};
            S_AR: {cmd, tx} = {OP_XFER, 8'hA1, 1'b1};
            S_READ: {cmd, tx} = {OP_XFER, 8'hFF, n == 8'd255};
            default: {cmd, tx} = {OP_XFER, 9'h1FF};  // S_RECOVER
        endcase
    end

    wire       busy;
    wire [8:0] rx;
    edid_i2c #(.QUARTER(QUARTER)) u_i2c (
        .clk(clk), .rst(rst || abort), .go(go), .cmd(cmd), .tx(tx), .busy(busy), .rx(rx),
        .scl_low(scl_low), .sda_low(sda_low), .scl_in(scl_in), .sda_in(sda_in));

    // A header byte NAKed: remember why and finish with a STOP.
    wire       header = (step == S_AW) || (step == S_OFF) || (step == S_AR);
    wire [2:0] nak_code = (step == S_AW) ? ST_NAK_AW : (step == S_OFF) ? ST_NAK_OFF : ST_NAK_AR;
    wire       done = issued && !go && !busy;   // the issued operation has finished

    always @(posedge clk) begin
        timer <= timer + 1'b1;
        abort <= 1'b0;
        go <= 1'b0;
        if (rst) begin
            {status, reads, timer} <= {ST_NONE, 8'd0, {PERIOD_BITS{1'b0}}};
            {step, issued, n, acc, err} <= {S_RECOVER, 1'b0, 8'd0, 8'd0, ST_OK};  // first attempt at once
        end else if (tick) begin
            if (step != S_WAIT) {status, abort} <= {ST_TIMEOUT, 1'b1};
            {step, issued, n, acc, err} <= {S_RECOVER, 1'b0, 8'd0, 8'd0, ST_OK};
        end else if (step != S_WAIT && !issued) begin
            {go, issued} <= 2'b11;
        end else if (done) begin
            issued <= 1'b0;
            if (header && rx[0]) {err, step} <= {nak_code, S_STOP};
            else if (step == S_READ) begin
                edid[n] <= rx[8:1];
                acc <= (n[2:0] == 3'd7) ? 8'd0 : acc + rx[8:1];
                if (n[2:0] == 3'd7) rowsum[n[7:3]] <= acc + rx[8:1];
                n <= n + 8'd1;
                if (n == 8'd255) step <= S_STOP;
            end else if (step == S_STOP) begin
                {step, status} <= {S_WAIT, err};
                if (err == ST_OK) reads <= reads + 8'd1;
            end else begin
                step <= step + 4'd1;
            end
        end
    end
endmodule

`default_nettype wire
