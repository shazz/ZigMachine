// WRITEBACK (cmd op 6, HW 1.9.0): the four palettes as the compositor holds them, out to the
// region's OFF_PAL in one 512-beat write burst. A copper list (zm_video_copper.v) writes palette
// entries the CPU never stored, and the browser's machine leaves them in memory, where a cart may
// read them back (a fade from the current colours): so after a frame with a list, the sequencer
// asks for this, and memory holds what the browser's does. Two palette reads a beat.
`default_nettype none

module zm_video_palwb (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [31:0] vbase,
    output wire        busy,
    output reg  [9:0]  pal_raddr,
    input  wire [31:0] pal_rdata,         // the clock after pal_raddr
    output wire        wr_req_valid,
    input  wire        wr_req_ready,
    output wire [31:0] wr_req_addr,
    output wire [9:0]  wr_req_len,
    output wire        wr_dat_valid,
    input  wire        wr_dat_ready,
    output wire [63:0] wr_dat,
    input  wire        wr_busy
);
`include "zm_video_memmap.vh"

    localparam [2:0] IDLE = 0, REQ = 1, A = 2, B = 3, C = 4, BEAT = 5, DRAIN = 6;
    reg [2:0] st = IDLE;
    reg [31:0] lo, hi;
    assign busy = st != IDLE;
    assign wr_req_valid = st == REQ;
    assign wr_req_addr = vbase + ZM_OFF_PAL;
    assign wr_req_len = 10'd512;
    assign wr_dat_valid = st == BEAT;
    assign wr_dat = {hi, lo};

    // A: the even word's address is out; B: it is read (the odd one's is out); C: the odd one is read.
    always @(posedge clk) begin
        if (rst) st <= IDLE;
        else case (st)
            IDLE: if (start) begin
                pal_raddr <= 10'd0;
                st <= REQ;
            end
            REQ: if (wr_req_ready) st <= A;
            A: begin
                pal_raddr <= pal_raddr + 10'd1;
                st <= B;
            end
            B: begin
                lo <= pal_rdata;
                st <= C;
            end
            C: begin
                hi <= pal_rdata;
                st <= BEAT;
            end
            BEAT: if (wr_dat_ready) begin
                pal_raddr <= pal_raddr + 10'd1;
                st <= pal_raddr == 10'd1023 ? DRAIN : A;
            end
            DRAIN: if (!wr_busy) st <= IDLE;
            default: st <= IDLE;
        endcase
    end
endmodule

`default_nettype wire
