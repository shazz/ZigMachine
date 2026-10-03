// Row I/O: moves one raster row between the frame buffer in memory and the
// compositor's line buffer and accumulator. A row is 800 pixels = 400 beats of
// 64 bits, pair x = {pixel 2x+1, pixel 2x} as the machine stores them.
//
//   LOAD   the PFB row (the canvas so far) into the line buffer, and, when the
//          pass folds into a picture that already has a layer, the picture's
//          row into the accumulator. Two read bursts, answered in order.
//   STORE  the line buffer back to the PFB row (when the pass painted it) and
//          the accumulator to the picture's row: write bursts, each beat read
//          from its RAM the clock before, through a 4-beat skid buffer so a
//          stalled port never loses one.
//
// The picture is stored as one 32-bit word a pixel, {0, B, G, R}: the RGB the
// scanout shows (zm_video_scanfetch.v reads it back the same way).
// The ports are zm_video_fetch.v's read port and the write port below:
//   wr_req_valid / ready / addr / len: one burst; then wr_len beats on
//   wr_dat_valid / wr_dat_ready / wr_dat, in order. wr_busy: the memory still
//   owes completions, so STORE is done only when it falls.
`default_nettype none

module zm_video_rowio (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] pfb_addr,       // this row in the PFB and in the picture,
    input  wire [31:0] d_addr,         //   held for the whole pass
    input  wire        ld_start,       // one clock, with:
    input  wire        ld_pfb, ld_d,   //   which rows to read
    output reg         ld_done,
    output wire        rd_req_valid,
    input  wire        rd_req_ready,
    output wire [31:0] rd_req_addr,
    output wire [9:0]  rd_req_len,
    input  wire        rd_rsp_valid,
    input  wire [63:0] rd_rsp_data,
    output wire        lb_we, acc_we,
    output wire [8:0]  ld_addr,
    output wire [63:0] ld_lb_data,
    output wire [47:0] ld_acc_data,
    input  wire        st_start,       // one clock, with:
    input  wire        st_pfb, st_d,   //   which rows to write
    output reg         st_done,
    output wire        wr_req_valid,
    input  wire        wr_req_ready,
    output wire [31:0] wr_req_addr,
    output wire [9:0]  wr_req_len,
    output wire        wr_dat_valid,
    input  wire        wr_dat_ready,
    output wire [63:0] wr_dat,
    input  wire        wr_busy,
    output wire [8:0]  st_raddr,
    input  wire [63:0] st_lb_rdata,    // the clock after st_raddr
    input  wire [47:0] st_acc_rdata
);
    localparam [8:0] LAST = 9'd399;
    assign rd_req_len = 10'd400;
    assign wr_req_len = 10'd400;

    // --- LOAD: lq = bursts still to ask for, lr = rows still arriving ({D, PFB}) ---
    reg [1:0] lq = 2'b00, lr = 2'b00;
    reg [8:0] rx;
    wire rx_d = !lr[0];                    // the PFB row (if any) comes first
    assign rd_req_valid = lq != 2'b00;
    assign rd_req_addr = lq[0] ? pfb_addr : d_addr;
    assign lb_we = rd_rsp_valid && lr[0];
    assign acc_we = rd_rsp_valid && rx_d && lr[1];
    assign ld_addr = rx;
    assign ld_lb_data = rd_rsp_data;
    assign ld_acc_data = {rd_rsp_data[55:32], rd_rsp_data[23:0]};

    always @(posedge clk) begin
        ld_done <= 1'b0;
        if (rst) {lq, lr} <= 4'b0;
        else if (ld_start) begin
            {lq, lr, rx} <= {ld_d, ld_pfb, ld_d, ld_pfb, 9'd0};
            ld_done <= !ld_d && !ld_pfb;
        end else begin
            if (rd_req_valid && rd_req_ready) lq <= lq[0] ? {lq[1], 1'b0} : 2'b00;
            if (lb_we || acc_we) begin
                rx <= rx == LAST ? 9'd0 : rx + 9'd1;
                if (rx == LAST) begin
                    lr <= rx_d ? 2'b00 : {lr[1], 1'b0};
                    ld_done <= rx_d || !lr[1];
                end
            end
        end
    end

    // --- STORE: sq = rows still to send ({D, PFB}), the current one's burst asked? ---
    reg [1:0] sq = 2'b00;
    reg       st_run = 1'b0, reqd = 1'b0, infl = 1'b0, infl_d = 1'b0;
    reg [8:0] ra, tx;
    reg [63:0] q [0:3];
    reg [1:0] head = 2'd0, tail = 2'd0;
    reg [2:0] count = 3'd0;
    wire tx_d = !sq[0];
    wire rd_go = reqd && ra <= LAST && count + {2'd0, infl} < 3'd3;
    wire pop = wr_dat_valid && wr_dat_ready;
    wire [63:0] acc_beat = {8'd0, st_acc_rdata[47:24], 8'd0, st_acc_rdata[23:0]};
    assign wr_req_valid = sq != 2'b00 && !reqd;
    assign wr_req_addr = tx_d ? d_addr : pfb_addr;
    assign st_raddr = ra;
    assign wr_dat_valid = count != 3'd0;
    assign wr_dat = q[head];

    always @(posedge clk) begin
        st_done <= 1'b0;
        {infl, infl_d} <= {rd_go && !rst, tx_d};
        if (infl) {q[tail], tail} <= {infl_d ? acc_beat : st_lb_rdata, tail + 2'd1};
        count <= count + {2'd0, infl} - {2'd0, pop};
        if (pop) head <= head + 2'd1;
        if (rst) {count, head, tail} <= 7'd0;
        if (rst) {sq, st_run, reqd} <= 4'b0;
        else if (st_start) {sq, st_run, reqd, ra, tx} <= {st_d, st_pfb, 1'b1, 1'b0, 9'd0, 9'd0};
        else begin
            if (wr_req_valid && wr_req_ready) reqd <= 1'b1;
            if (rd_go) ra <= ra + 9'd1;
            if (pop) tx <= tx + 9'd1;
            if (pop && tx == LAST) {sq, reqd, ra, tx} <= {tx_d ? 2'b00 : {sq[1], 1'b0}, 1'b0, 9'd0, 9'd0};
            if (st_run && sq == 2'b00 && !wr_busy) {st_run, st_done} <= 2'b01;
        end
    end
endmodule

`default_nettype wire
