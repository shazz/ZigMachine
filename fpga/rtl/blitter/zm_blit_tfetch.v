// The words zm_blit_tex walks, streamed through the core's aux read port into a 32-word FIFO
// (LUTRAM), in the order the walker pops them:
//   AFFINE: the span list, 6 words a span, from `list` (4-aligned: the check refuses others);
//   MAP:    per row of the clipped box, the words holding its entries, from the row's first
//           entry (list + (y - Y0) * ms + 2 * (ex0 - X0)) to its last.
// A read is asked only while its answer has a free FIFO slot (the FIFO's words + the reads in
// flight < 32): the port's answers come back in order and cannot be refused. Both the list and
// the map live in cart RAM or the ROM window, which CHISEL never writes, so these reads may run
// ahead of every write of the op.
`default_nettype none

module zm_blit_tfetch (
    input  wire               clk,
    input  wire               rst,
    input  wire               go_aff, go_map,
    input  wire [22:0]        list,
    input  wire [15:0]        nspan, ms,
    input  wire signed [17:0] x0, y0, ex0, ey0, ex1, ey1,
    output wire               aux_valid,
    input  wire               aux_ready,
    output wire [22:0]        aux_addr,
    input  wire               rsp_valid,
    input  wire [31:0]        rsp_data,
    output wire               q_valid,
    output wire [31:0]        q_word,
    input  wire               q_pop
);
    localparam [2:0] IDLE = 0, PROD = 1, FIRST = 2, RANGE = 3, RUN = 4;
    reg [2:0] st;
    reg [20:0] wa, wlast;                        // word addresses: the next to ask, the range's last
    reg [17:0] rows;                             // MAP: rows left after this one
    reg [22:0] rsb, len2;                        // MAP: the row's first entry's byte, 2 * entries a row
    reg [33:0] p;                                // MAP: (ey0 - Y0) * ms
    reg [1:0] pc;
    wire [17:0] dy0 = ey0 - y0;                  // >= 0 (the box starts at or below Y0); 18 bits, so no sign mixes in

    // the FIFO and its credit
    reg [31:0] mem [0:31];
    reg [5:0] wp, rp, inflight;
    wire [5:0] used = (wp - rp) + inflight;
    assign q_valid = wp != rp;
    assign q_word = mem[rp[4:0]];
    assign aux_valid = st == RUN && used < 6'd32;
    assign aux_addr = {wa, 2'b00};
    wire take = aux_valid && aux_ready;
    always @(posedge clk) if (rsp_valid) mem[wp[4:0]] <= rsp_data;

    always @(posedge clk) begin
        if (rst) begin st <= IDLE; wp <= 6'd0; rp <= 6'd0; inflight <= 6'd0; end
        else begin
            if (rsp_valid) wp <= wp + 6'd1;
            if (q_pop) rp <= rp + 6'd1;
            inflight <= inflight + (take ? 6'd1 : 6'd0) - (rsp_valid ? 6'd1 : 6'd0);
            case (st)
                IDLE: if (go_aff && nspan != 16'd0) begin
                    wa <= list[22:2]; wlast <= list[22:2] + {3'd0, nspan, 2'b00} + {4'd0, nspan, 1'b0} - 21'd1;
                    rows <= 18'd0; st <= RUN;
                end else if (go_map && ex1 > ex0 && ey1 > ey0) begin
                    rows <= ey1 - ey0 - 18'sd1; len2 <= {4'd0, ex1 - ex0, 1'b0}; pc <= 2'd0; st <= PROD;
                end
                PROD: begin  // a product a clock behind its operands, two clocks to settle
                    p <= dy0 * ms;
                    pc <= pc + 2'd1;
                    if (pc == 2'd1) st <= FIRST;
                end
                FIRST: begin rsb <= list + p[22:0] + {4'd0, ex0 - x0, 1'b0}; st <= RANGE; end
                RANGE: begin wa <= rsb[22:2]; wlast <= (rsb + len2 - 23'd1) >> 2; st <= RUN; end
                default: if (take) begin  // RUN
                    wa <= wa + 21'd1;
                    if (wa == wlast) begin
                        if (rows == 18'd0) st <= IDLE;
                        else begin rows <= rows - 18'd1; rsb <= rsb + {7'd0, ms}; st <= RANGE; end
                    end
                end
            endcase
        end
    end
endmodule
