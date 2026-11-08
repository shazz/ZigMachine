// Scanout fetch: reads the shown picture out of memory, a raster line ahead of
// the beam, into the two display line buffers (zm_video_dcram.v) the scanout
// reads in the pixel clock. One read burst a line: 400 beats, {pixel 2x+1,
// pixel 2x} as {0, B, G, R} words (zm_video_rowio.v writes them so). A beat
// goes into the buffer whole; the scanout picks its pixels.
//
// Desk mode (`desk`, HW 1.17.0, sampled with the base at the VBL): plane 0's
// bytes straight from the VRAM pool, 80 beats a line (640 indices), 480 lines
// from `desk_base` at stride 640. The line address is a running sum: the frame's
// base, plus the stride after each line.
//
// Line y goes to buffer y[0] once the scanout has freed it (`dp_free`), and is
// published (`line_ready`) when its last beat is in. After line 279 the fetch
// waits for the VBL, where zm_video_out.v swaps the pictures, and samples the
// picture to show (`base`, or `desk_base`) then: a frame on the screen is always ONE picture.
// It starts at reset as if a VBL had just happened.
//
// Only a VBL seen WHILE waiting counts. The frees come one a raster line
// whatever the buffers hold, so a fetch that starts out of phase (on the board
// HP1 is gated until CTRL.RUN, which lands anywhere in a frame) stays out of
// phase line for line; a VBL remembered from mid-frame restarted it at once
// and kept it there forever (all black, 2026-10-09). Waiting for a fresh VBL
// costs one black frame and locks the fetch to the beam.
`default_nettype none

module zm_video_scanfetch (
    input  wire        clk,
    input  wire        rst,
    input  wire        vbl,            // one clock, in clk's domain
    input  wire [31:0] base,           // bus address of the picture to show, sampled at the VBL
    input  wire        desk,           // ... the mode of the frame to show
    input  wire [31:0] desk_base,      // ... and plane 0's bus address (8-byte aligned)
    input  wire [1:0]  dp_free,        // display buffer b may be overwritten
    output wire        rd_req_valid,
    input  wire        rd_req_ready,
    output wire [31:0] rd_req_addr,
    output wire [9:0]  rd_req_len,
    input  wire        rd_rsp_valid,
    input  wire [63:0] rd_rsp_data,
    output wire        dp_we,
    output wire [9:0]  dp_waddr,       // {buffer, pair}
    output wire [63:0] dp_wdata,
    output reg         line_ready,     // one clock: line `ready_line` is in its buffer
    output reg  [8:0]  ready_line
);
`include "zm_video_memmap.vh"

    localparam [1:0] FRAME = 2'd0, FREE = 2'd1, ASK = 2'd2, RECV = 2'd3;
    reg [1:0]  st = FREE;
    reg [8:0]  y = 9'd0, rx;
    reg [31:0] addr;                   // this line's bus address
    reg        dk = 1'b0;              // this frame is a desk frame
    wire [31:0] start = desk ? desk_base : base;
    wire [31:0] stride = dk ? ZM_DESK_WIDTH : 32'd3200;  // a picture line: 400 beats of 8 bytes
    wire [8:0]  last_rx = dk ? ZM_DESK_WIDTH / 8 - 1 : 9'd399;
    wire [8:0]  last_y = dk ? ZM_DESK_HEIGHT - 1 : ZM_RASTER_HEIGHT - 1;

    assign rd_req_valid = st == ASK;
    assign rd_req_addr = addr;
    assign rd_req_len = dk ? ZM_DESK_WIDTH / 8 : 10'd400;
    assign dp_we = st == RECV && rd_rsp_valid;
    assign dp_waddr = {y[0], rx};
    assign dp_wdata = rd_rsp_data;

    always @(posedge clk) begin
        line_ready <= 1'b0;
        if (rst) begin
            {st, y} <= {FREE, 9'd0};
            {addr, dk} <= {start, desk};
        end else begin
            case (st)
                FRAME: if (vbl) {st, addr, dk} <= {FREE, start, desk};
                FREE: if (dp_free[y[0]]) st <= ASK;
                ASK: if (rd_req_ready) {st, rx} <= {RECV, 9'd0};
                RECV: if (rd_rsp_valid) begin
                    rx <= rx + 9'd1;
                    if (rx == last_rx) begin
                        {line_ready, ready_line, addr} <= {1'b1, y, addr + stride};
                        if (y == last_y) {st, y} <= {FRAME, 9'd0};
                        else {st, y} <= {FREE, y + 9'd1};
                    end
                end
            endcase
        end
    end
endmodule

`default_nettype wire
