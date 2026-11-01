// The blitter's sequencer: what a kick (a non-zero COMMAND store, zm_blit_regs) starts.
// It owns the op bank's write port and the engine's start:
//   COPY  the tap bank (memory's block) into the op bank, a word a clock, at EVERY kick, so
//         an op never sees a store made after its kick, and none is ever dropped;
//   then one op (COMMAND 1..4, or an unknown one the engine refuses), or for COMMAND 5
//   (QUEUE) the descriptor list in the ring: per descriptor a header (bits 0..23 the mask of
//   block words that follow, bits 24..31 the op's COMMAND), its words lowest first into the
//   op bank, then the op, to its end, before the next header. COMMAND 0 only sets words.
// The ring is a block RAM copy of memory's QUEUE ring (memmap OFF_BLIT_QUEUE), fed by the
// CPU's stores like the tap bank; the kick's word carries the list: start in [16:8], count in
// [26:17]. The list ends at its count, also in the middle of a descriptor (that one never
// runs). A queued op whose D_BASE is below OFF_VRAM is refused (no op, cost 0): a list draws
// into planes, never the registers and palettes the compositor snoops. BUSY covers all of it.
// machine/blitter_queue.zig is the same list run at once.
`default_nettype none
`include "memmap.vh"

module zm_blit_q (
    input  wire         clk,
    input  wire         rst,
    input  wire         kick,
    input  wire [31:0]  kick_data,
    input  wire         q_we,            // a store to the ring: word index, byte enables
    input  wire [8:0]   q_waddr,
    input  wire [3:0]   q_be,
    input  wire [31:0]  q_wdata,
    output wire [4:0]   t_raddr,         // the tap bank (zm_blit_regs)
    input  wire [31:0]  t_rdata,
    output reg          ld_we,           // the op bank's write port
    output reg  [4:0]   ld_word,
    output reg  [3:0]   ld_be,
    output reg  [31:0]  ld_data,
    output wire         core_start,
    input  wire         core_busy,
    input  wire [31:0]  d_base,          // the op bank's D_BASE: a queued op below OFF_VRAM is refused
    output wire         busy,
    output wire         copying          // the tap bank is being read: no store may reach it now
);
    localparam [3:0] IDLE = 0, COPY = 1, HDR = 2, HDR2 = 3, WRD = 4, WRD2 = 5, SET = 6, SETTLE = 7,
                     GO = 8, WAIT1 = 9, WAIT = 10;
    reg [3:0] st;
    reg [4:0] idx;
    reg [8:0] ptr;
    reg [9:0] left;          // ring words still in the list
    reg [23:0] mask;         // the words of this descriptor not yet loaded
    reg [7:0] ocmd;          // this op's COMMAND
    reg is_q;

    reg [31:0] ring [0:511];
    reg [31:0] rd;           // ring[ptr], a clock late
    integer b;
    always @(posedge clk) begin
        for (b = 0; b < 4; b = b + 1)
            if (q_we && q_be[b]) ring[q_waddr][b*8 +: 8] <= q_wdata[b*8 +: 8];
        rd <= ring[ptr];
    end

    function [4:0] lowest(input [23:0] m);  // the lowest set bit's index (0 when none)
        integer k;
        begin
            lowest = 5'd0;
            for (k = 23; k >= 0; k = k - 1) if (m[k]) lowest = k[4:0];
        end
    endfunction

    assign t_raddr = idx;
    assign core_start = st == GO;
    assign busy = st != IDLE;
    assign copying = st == COPY;

    always @(posedge clk) begin
        ld_we <= 1'b0;
        if (rst) st <= IDLE;
        else case (st)
            IDLE: if (kick) begin
                ocmd <= kick_data[7:0];
                is_q <= kick_data[7:0] == ZM_BLIT_CMD_QUEUE;
                ptr <= kick_data[16:8];
                left <= kick_data[26:17];
                idx <= 5'd0;
                st <= COPY;
            end
            COPY: begin  // word 0: MINTERM and CON; COMMAND is the op's own (SET)
                ld_we <= 1'b1; ld_word <= idx; ld_be <= idx == 5'd0 ? 4'b0110 : 4'b1111; ld_data <= t_rdata;
                idx <= idx + 5'd1;
                if (idx == 5'd23) st <= is_q ? HDR : SET;
            end
            HDR: st <= left == 10'd0 ? IDLE : HDR2;
            HDR2: begin
                mask <= rd[23:0]; ocmd <= rd[31:24];
                ptr <= ptr + 9'd1; left <= left - 10'd1;
                st <= WRD;
            end
            WRD: st <= mask == 24'd0 ? SET : left == 10'd0 ? IDLE : WRD2;
            WRD2: begin
                ld_we <= 1'b1; ld_word <= lowest(mask); ld_be <= mask[0] ? 4'b0110 : 4'b1111; ld_data <= rd;
                mask <= mask & (mask - 24'd1);
                ptr <= ptr + 9'd1; left <= left - 10'd1;
                st <= WRD;
            end
            SET: begin
                ld_we <= 1'b1; ld_word <= 5'd0; ld_be <= 4'b0001; ld_data <= {24'd0, ocmd};
                st <= ocmd != 8'd0 && (!is_q || d_base >= ZM_OFF_VRAM) ? SETTLE : is_q ? HDR : IDLE;
            end
            SETTLE: st <= GO;  // the op bank has the op's last word: the engine starts a clock later
            GO: st <= WAIT1;
            WAIT1: st <= WAIT;
            WAIT: if (!core_busy) st <= is_q ? HDR : IDLE;
            default: st <= IDLE;
        endcase
    end
endmodule
