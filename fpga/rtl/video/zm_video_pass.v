// Pass sequencing: the phases of one BG, PLANE or MIX pass over raster line y.
//
// The machine renders plane-major (video.zig: hwClear paints all 280 lines,
// then each hwRenderPlane composites one plane over all 280), so between two
// passes over the same line every other line has been through the compositor,
// and the line lives in memory: the PFB in the region, as the machine keeps it,
// and the picture (the browser's stacked canvases) in a frame buffer. A pass:
//
//   BG     PAINT the line from BACKGROUND / BEAM                -> STORE PFB
//   PLANE  LOAD PFB (+ picture) -> PAINT the plane -> MIX       -> STORE PFB (if painted) + picture
//   MIX    LOAD PFB (+ picture) ->                    MIX       -> STORE picture
//
// MIX is a PLANE pass that paints nothing: the cleared PFB shown on its own when
// no plane is enabled. `first`: the line's first fold of the frame, over the
// tube, so the picture row is not loaded. `painted` pulses once the pass has
// read everything the CPU can change (registers, palettes, the BEAM table):
// from then on the next HBL handler may run while the pass mixes and stores.
`default_nettype none

module zm_video_pass (
    input  wire        clk,
    input  wire        rst,
    input  wire        take,           // a BG / PLANE / MIX command is taken
    input  wire [2:0]  op,
    input  wire [8:0]  line,
    input  wire        mix, first,
    input  wire [31:0] vbase,          // bus address of region offset 0
    input  wire [31:0] dbase,          // bus address of the picture being built
    output reg  [31:0] pfb_addr, d_addr,
    output reg         busy = 1'b0,
    output reg         fetching = 1'b0,// the plane path owns the read port
    output reg         start_bg, start_pl, start_mix, mix_first,
    input  wire        bg_done, pl_done, mix_done,
    output reg         ld_start, ld_pfb, ld_d,
    input  wire        ld_done,
    output reg         st_start, st_pfb, st_d,
    input  wire        st_done,
    input  wire        lb_painted,     // the plane path wrote the line buffer this pass
    output reg         painted,        // one clock: the CPU may change state again
    output reg         done
);
`include "zm_video_memmap.vh"

    localparam [2:0] IDLE = 3'd0, LOAD = 3'd1, PAINT = 3'd2, MIX = 3'd3, STORE = 3'd4;
    localparam [2:0] OP_BG = 3'd0, OP_PLANE = 3'd1, OP_MIX = 3'd3;
    reg [2:0] st = IDLE;
    reg       is_bg, is_pl, p_mix, p_first, dirty;
    wire [31:0] row = {12'd0, line, 11'd0} + {13'd0, line, 10'd0} + {16'd0, line, 7'd0};  // y * 3200

    always @(posedge clk) begin
        {start_bg, start_pl, start_mix, ld_start, st_start, painted, done} <= 7'b0;
        if (st == IDLE || take) dirty <= 1'b0;
        else if (lb_painted) dirty <= 1'b1;
        if (take) begin
            pfb_addr <= vbase + ZM_OFF_PFB + row;
            d_addr <= dbase + row;
            {is_bg, is_pl, p_mix, p_first} <= {op == OP_BG, op == OP_PLANE, mix, first};
            mix_first <= first;
        end
        if (rst) {st, busy, fetching} <= {IDLE, 2'b00};
        else case (st)
            IDLE: if (take && (op == OP_BG || op == OP_PLANE || op == OP_MIX)) begin
                busy <= 1'b1;
                if (op == OP_BG) {st, start_bg} <= {PAINT, 1'b1};
                else {st, ld_start, ld_pfb, ld_d} <= {LOAD, 1'b1, 1'b1, mix && !first};
            end
            LOAD: if (ld_done) begin
                if (is_pl) {st, start_pl, fetching} <= {PAINT, 2'b11};
                else {st, painted, start_mix} <= {MIX, 1'b1, p_mix};
            end
            PAINT: if (is_bg ? bg_done : pl_done) begin
                {painted, fetching} <= 2'b10;
                if (is_pl && p_mix) {st, start_mix} <= {MIX, 1'b1};
                else {st, st_start, st_pfb, st_d} <= {STORE, 1'b1, is_bg || dirty, 1'b0};
            end
            MIX: if (mix_done || !p_mix) {st, st_start, st_pfb, st_d} <= {STORE, 1'b1, is_pl && dirty, p_mix};
            STORE: if (st_done) {st, busy, done} <= {IDLE, 2'b01};
            default: st <= IDLE;
        endcase
    end
endmodule

`default_nettype wire
