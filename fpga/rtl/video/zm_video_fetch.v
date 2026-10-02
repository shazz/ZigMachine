// Line fetcher: copies one plane line's source bytes from memory into the fetch
// buffer, as whole 32-bit words.
//
// THE READ PORT (the only way the compositor reaches memory):
//   request : mem_req_valid / mem_req_ready / mem_req_addr. A request is taken
//             on a clock where valid and ready are both high. The address is a
//             byte offset from HW_VIDEO_BASE, always a multiple of 4.
//   response: mem_rsp_valid / mem_rsp_data, one per request, IN REQUEST ORDER,
//             any number of clocks later. There is no back-pressure on
//             responses: the buffer always has room for every word asked for.
// That is the shape of an AXI read channel with in-order IDs (AR = request,
// R = response, RREADY tied high), so this can sit behind an AXI HP master to
// DDR without changing. Several requests may be outstanding.
//
// A line's bytes start at any byte (FB_BASE, row * stride and HSCROLL are byte
// granular), so the words cover [addr & ~3, addr + nbytes) and `align` =
// addr[1:0] tells the painter where byte 0 sits in word 0.
`default_nettype none

module zm_video_fetch (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,          // one-clock pulse; the inputs below are held
    input  wire [31:0] addr,
    input  wire [10:0] nbytes,         // 1..1021
    output reg         done,           // one-clock pulse: every word is in the buffer
    output reg         overflow,       // sticky: a line wanted more than 256 words
    output wire        mem_req_valid,
    input  wire        mem_req_ready,
    output wire [31:0] mem_req_addr,
    input  wire        mem_rsp_valid,
    input  wire [31:0] mem_rsp_data,
    output wire        buf_we,
    output wire [7:0]  buf_waddr,
    output wire [31:0] buf_wdata
);
    localparam integer MAX_WORDS = 256;

    reg        busy = 1'b0;
    reg [31:0] next_addr;
    reg [8:0]  to_ask, to_get;   // words still to request / still to receive
    reg [7:0]  got;              // buffer index of the next response
    wire [12:0] span = {11'd0, addr[1:0]} + {2'd0, nbytes} + 13'd3;
    wire [10:0] words = span[12:2];

    assign mem_req_valid = busy && to_ask != 9'd0;
    assign mem_req_addr = next_addr;
    assign buf_we = busy && mem_rsp_valid;
    assign buf_waddr = got;
    assign buf_wdata = mem_rsp_data;

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) begin
            busy <= 1'b0;
            overflow <= 1'b0;
        end else if (start) begin
            busy <= 1'b1;
            next_addr <= {addr[31:2], 2'b00};
            to_ask <= words > MAX_WORDS ? 9'd256 : words[8:0];
            to_get <= words > MAX_WORDS ? 9'd256 : words[8:0];
            got <= 8'd0;
            if (words > MAX_WORDS) overflow <= 1'b1;
        end else if (busy) begin
            if (mem_req_valid && mem_req_ready) begin
                next_addr <= next_addr + 32'd4;
                to_ask <= to_ask - 9'd1;
            end
            if (mem_rsp_valid) begin
                got <= got + 8'd1;
                to_get <= to_get - 9'd1;
                if (to_get == 9'd1) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end
            end
        end
    end
endmodule

`default_nettype wire
