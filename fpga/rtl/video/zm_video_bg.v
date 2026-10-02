// Background pass: paints one raster line from REG_BACKGROUND, or, when the
// global HBL queued BEAM writes (BEAM_COUNT != 0), in spans from the BEAM table
// (machine/beam.zig paintLine, rule for rule):
//   - an entry is x:u16 (low-res px, high half) | an ST colour word (low half);
//   - x snaps down to BEAM_GRID; it is DROPPED if x >= PHYSICAL_WIDTH or it is
//     less than BEAM_MIN_GAP after the last accepted write;
//   - at most BEAM_MAX entries are read, the rest of BEAM_COUNT count as drops.
// It writes one low-res pixel (a doubled pair) a clock into the line buffer.
`default_nettype none

module zm_video_bg (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        last_line,      // this is raster line 279: FRAME + 1 after it
    input  wire [31:0] bg,             // REG_BACKGROUND
    input  wire [15:0] count,          // REG_BEAM_COUNT
    output wire [5:0]  beam_raddr,
    input  wire [31:0] beam_rdata,     // the clock after beam_raddr
    output reg         lb_we,
    output reg  [8:0]  lb_addr,        // pair (low-res pixel) 0..399
    output reg  [31:0] lb_data,
    output reg         done,
    output reg         beam_upd,       // BEAM line: write back colour + drops
    output reg  [31:0] beam_bg,
    output reg  [31:0] beam_drops,
    output reg         frame_inc
);
`include "zm_video_memmap.vh"

    localparam [2:0] IDLE = 3'd0, READ = 3'd1, LOAD = 3'd2, EVAL = 3'd3, FILL = 3'd4;
    reg [2:0]  st = IDLE;
    reg [8:0]  x;                  // next pair to paint
    reg [6:0]  i, n;               // entry index, entries to read (min(count, 64))
    reg [31:0] colour, e;
    reg [8:0]  from;
    reg        have_prev, beam, last;
    wire [15:0] ex = e[31:16] & ~(ZM_BEAM_GRID[15:0] - 16'd1);
    wire       drop = ex >= ZM_PHYSICAL_WIDTH || (have_prev && ex < {7'd0, from} + ZM_BEAM_MIN_GAP);
    assign beam_raddr = i[5:0];

    // ST colour word $0RGB -> RGBA (beam.zig stToRgba): a 4-bit STE level x 16.
    function automatic [7:0] gun(input [3:0] nib);
        gun = {nib[2:0], nib[3], 4'd0};
    endfunction
    wire [31:0] st_rgba = {8'hFF, gun(e[3:0]), gun(e[7:4]), gun(e[11:8])};

    task automatic paint;
        begin
            lb_we <= 1'b1;
            lb_addr <= x;
            lb_data <= colour;
            x <= x + 9'd1;
        end
    endtask

    task automatic begin_line;        // the line's starting state, from the registers
        begin
            {x, i, have_prev, colour, beam, last} <= {9'd0, 7'd0, 1'b0, bg, count != 16'd0, last_line};
            n <= count > ZM_BEAM_MAX ? ZM_BEAM_MAX[6:0] : count[6:0];
            beam_drops <= count > ZM_BEAM_MAX ? {16'd0, count} - ZM_BEAM_MAX : 32'd0;
            st <= count != 16'd0 ? READ : FILL;
        end
    endtask

    task automatic finish_line;       // write-backs: the line's last colour, its drops
        begin
            st <= IDLE;
            done <= 1'b1;
            beam_upd <= beam;
            beam_bg <= colour;
            frame_inc <= last;
        end
    endtask

    always @(posedge clk) begin
        {lb_we, done, beam_upd, frame_inc} <= 4'b0;
        if (rst) st <= IDLE;
        else case (st)
            IDLE: if (start) begin_line;
            READ: st <= i == n ? FILL : LOAD;    // beam_raddr = i this clock
            LOAD: {e, st} <= {beam_rdata, EVAL};
            EVAL:
                if (drop) {beam_drops, i, st} <= {beam_drops + 32'd1, i + 7'd1, READ};
                else if ({7'd0, x} < ex) paint;
                else begin                         // x == ex: the colour changes here
                    {colour, from, have_prev} <= {st_rgba, x, 1'b1};
                    {i, st} <= {i + 7'd1, READ};
                end
            FILL: if (x != ZM_PHYSICAL_WIDTH) paint; else finish_line;
            default: st <= IDLE;
        endcase
    end
endmodule

`default_nettype wire
