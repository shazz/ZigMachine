// Line fetcher: copies one plane line's source bytes from memory into the fetch
// buffer, as one burst of 64-bit beats.
//
// THE READ PORT (rtl/video/README.md "Memory"): a request is a burst,
//   rd_req_valid / rd_req_ready / rd_req_addr (a byte address, a multiple of 8)
//   / rd_req_len (beats), taken on a clock where valid and ready are both high;
//   rd_rsp_valid / rd_rsp_data: the beats, IN REQUEST ORDER, any number of
//   clocks apart, with no back-pressure (the buffer has room for every beat).
// That is an AXI read channel (AR = request, R = beats, RREADY tied high); the
// DMA (soc/zm_video_dma.py) turns it into bus bursts.
//
// A line's bytes start at any byte (FB_BASE, row * stride and HSCROLL are byte
// granular). The beats cover [addr & ~7, addr + nbytes); the painter addresses
// 32-bit words counted from `addr & ~3`, which is word `addr[2]` of the buffer
// (zm_video_planepath.v maps one to the other).
`default_nettype none

module zm_video_fetch (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,          // one-clock pulse; the inputs below are held
    input  wire [31:0] addr,
    input  wire [10:0] nbytes,         // 1..1021
    output reg         done,           // one-clock pulse: every beat is in the buffer
    output reg         overflow,       // sticky: a line wanted more than 256 words
    output wire        rd_req_valid,
    input  wire        rd_req_ready,
    output wire [31:0] rd_req_addr,
    output wire [9:0]  rd_req_len,
    input  wire        rd_rsp_valid,
    input  wire [63:0] rd_rsp_data,
    output wire        buf_we,
    output wire [7:0]  buf_waddr,
    output wire [63:0] buf_wdata
);
    localparam integer MAX_WORDS = 256;

    reg        busy = 1'b0, asked = 1'b0;
    reg [8:0]  to_get;           // beats still to receive
    reg [7:0]  got;              // buffer index of the next beat
    reg [8:0]  beats_r;
    wire [12:0] span = {11'd0, addr[1:0]} + {2'd0, nbytes} + 13'd3;
    wire [10:0] words = span[12:2];
    // Beats covering the same bytes from the 8-byte boundary below addr.
    wire [12:0] bspan = {10'd0, addr[2:0]} + {2'd0, nbytes} + 13'd7;
    wire [8:0]  beats = bspan[11:3];

    assign rd_req_valid = busy && !asked;
    assign rd_req_addr = {addr[31:3], 3'b000};
    assign rd_req_len = {1'b0, beats_r};
    assign buf_we = busy && asked && rd_rsp_valid;
    assign buf_waddr = got;
    assign buf_wdata = rd_rsp_data;

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) begin
            {busy, asked, overflow} <= 3'b000;
        end else if (start) begin
            // A line too long for the buffer is flagged and not fetched at all.
            busy <= words <= MAX_WORDS;
            done <= words > MAX_WORDS;
            if (words > MAX_WORDS) overflow <= 1'b1;
            asked <= 1'b0;
            {beats_r, to_get, got} <= {beats, beats, 8'd0};
        end else if (busy) begin
            if (rd_req_valid && rd_req_ready) asked <= 1'b1;
            if (buf_we) begin
                got <= got + 8'd1;
                to_get <= to_get - 9'd1;
                if (to_get == 9'd1) {busy, done} <= 2'b01;
            end
        end
    end
endmodule

`default_nettype wire
