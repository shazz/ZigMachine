// Scanout fetch: reads the shown picture out of memory, a raster line ahead of
// the beam, into the two display line buffers (zm_video_dcram.v) the scanout
// reads in the pixel clock. One read burst a line: 400 beats, {pixel 2x+1,
// pixel 2x} as {0, B, G, R} words (zm_video_rowio.v writes them so).
//
// Line y goes to buffer y[0] once the scanout has freed it (`dp_free`), and is
// published (`line_ready`) when its last beat is in. After line 279 the fetch
// waits for the VBL, where zm_video_out.v swaps the pictures, and samples the
// picture to show (`base`) then: a frame on the screen is always ONE picture.
// It starts at reset as if a VBL had just happened.
`default_nettype none

module zm_video_scanfetch (
    input  wire        clk,
    input  wire        rst,
    input  wire        vbl,            // one clock, in clk's domain
    input  wire [31:0] base,           // bus address of the picture to show, sampled at the VBL
    input  wire [1:0]  dp_free,        // display buffer b may be overwritten
    output wire        rd_req_valid,
    input  wire        rd_req_ready,
    output wire [31:0] rd_req_addr,
    output wire [9:0]  rd_req_len,
    input  wire        rd_rsp_valid,
    input  wire [63:0] rd_rsp_data,
    output wire        dp_we,
    output wire [9:0]  dp_waddr,       // {buffer, pair}
    output wire [47:0] dp_wdata,
    output reg         line_ready,     // one clock: line `ready_line` is in its buffer
    output reg  [8:0]  ready_line
);
`include "zm_video_memmap.vh"

    localparam [1:0] FRAME = 2'd0, FREE = 2'd1, ASK = 2'd2, RECV = 2'd3;
    reg [1:0]  st = FREE;
    reg [8:0]  y = 9'd0, rx;
    reg [31:0] fbase;
    reg        vbl_seen = 1'b0;
    wire [31:0] row = {12'd0, y, 11'd0} + {13'd0, y, 10'd0} + {16'd0, y, 7'd0};  // y * 3200

    assign rd_req_valid = st == ASK;
    assign rd_req_addr = fbase + row;
    assign rd_req_len = 10'd400;
    assign dp_we = st == RECV && rd_rsp_valid;
    assign dp_waddr = {y[0], rx};
    assign dp_wdata = {rd_rsp_data[55:32], rd_rsp_data[23:0]};

    always @(posedge clk) begin
        line_ready <= 1'b0;
        if (rst) begin
            {st, y, vbl_seen} <= {FREE, 9'd0, 1'b0};
            fbase <= base;
        end else begin
            if (vbl) vbl_seen <= 1'b1;
            case (st)
                FRAME: if (vbl || vbl_seen) {st, fbase, vbl_seen} <= {FREE, base, 1'b0};
                FREE: if (dp_free[y[0]]) st <= ASK;
                ASK: if (rd_req_ready) {st, rx} <= {RECV, 9'd0};
                RECV: if (rd_rsp_valid) begin
                    rx <= rx + 9'd1;
                    if (rx == 9'd399) begin
                        {line_ready, ready_line} <= {1'b1, y};
                        if (y == ZM_RASTER_HEIGHT - 1) {st, y} <= {FRAME, 9'd0};
                        else {st, y} <= {FREE, y + 9'd1};
                    end
                end
            endcase
        end
    end
endmodule

`default_nettype wire
