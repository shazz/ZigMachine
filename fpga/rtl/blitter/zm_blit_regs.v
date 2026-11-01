// The blitter register block (memmap BLIT_*, region offsets 0x80..0xDF), written the way
// the CPU writes the machine region: a word index, byte enables, a 32-bit word. A store of
// COMMAND with a non-zero byte is a KICK (the Zig machine runs the op on hwBlit() after the
// same register writes); its upper 24 bits carry a QUEUE's range (zm_blit_q.v).
//
// Two banks, so a store is never dropped:
// - the TAP bank, written by every store at any time, is memory's block (a LUT RAM: 32 words
//   in four byte lanes, read a word at a time);
// - the OP bank, what the engine reads, is loaded only by the sequencer (zm_blit_q): the tap
//   bank copied word by word at a kick, then a QUEUE's descriptor words. Words 0..15 are
//   flops (`rf`, word w = rf[w*32 +: 32]); the halftone (words 16..23) is LUTRAM below.
// While an op runs the cart may store the next op's registers: they wait in the tap bank.
// Words 7 and 9 keep their low 16 bits only; words 3 and 5 hold U_MASK / V_MASK above the
// strides (CHISEL v2). CYCLES restarts at each kick and adds every op's cost: one op's, or a
// QUEUE's sum. STATUS (bit 31 BUSY) and CYCLES are the only words read back.
`default_nettype none

module zm_blit_regs (
    input  wire         clk,
    input  wire         rst,
    input  wire         cpu_we,
    input  wire [4:0]   cpu_waddr,       // word index in the block (offset / 4)
    input  wire [3:0]   cpu_be,
    input  wire [31:0]  cpu_wdata,
    input  wire [4:0]   cpu_raddr,
    output wire [31:0]  cpu_rdata,       // combinational: STATUS (word 0, bit 31) and CYCLES (word 24)
    input  wire         busy,            // the sequencer or the engine is at work
    input  wire [15:0]  dbg,             // STATUS[15:0], the engine's state (zm_blit_core dbg)
    input  wire         cyc_we,          // the engine's cost of an op
    input  wire [31:0]  cyc_val,
    input  wire         coll_hit,        // CON2.COLL_EN: a pixel landed on a non-zero byte
    output reg          kick,            // one clock: COMMAND was written non-zero
    output reg  [31:0]  kick_data,       // that store's word: COMMAND in [7:0]
    input  wire [4:0]   t_raddr,         // the tap bank, read by the sequencer
    output wire [31:0]  t_rdata,
    input  wire         ld_we,           // the op bank's one write port (the sequencer)
    input  wire [4:0]   ld_word,
    input  wire [3:0]   ld_be,
    input  wire [31:0]  ld_data,
    output wire [511:0] rf,
    input  wire [3:0]   ht_y,            // a halftone row, read combinationally
    output wire [15:0]  ht_row,
    output wire         ht_nz            // some halftone byte is not zero (the pre-1.5.0 sniff)
);
    (* use_dsp = "yes" *) reg [31:0] cycles;   // a DSP48 accumulator, not a CARRY4 chain (slices)
    reg coll;                            // since the kick (the firmware ORs it into BLIT_COLL)
    wire go = cpu_we && cpu_waddr == 5'd0 && cpu_be[0] && cpu_wdata[7:0] != 8'd0;

    reg [7:0] tap0 [0:31];
    reg [7:0] tap1 [0:31];
    reg [7:0] tap2 [0:31];
    reg [7:0] tap3 [0:31];
    always @(posedge clk) if (cpu_we) begin
        if (cpu_be[0]) tap0[cpu_waddr] <= cpu_wdata[7:0];
        if (cpu_be[1]) tap1[cpu_waddr] <= cpu_wdata[15:8];
        if (cpu_be[2]) tap2[cpu_waddr] <= cpu_wdata[23:16];
        if (cpu_be[3]) tap3[cpu_waddr] <= cpu_wdata[31:24];
    end
    assign t_rdata = {tap3[t_raddr], tap2[t_raddr], tap1[t_raddr], tap0[t_raddr]};

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : g
            reg [31:0] r;
            wire hit = ld_we && ld_word == i;
            wire narrow = (i == 7) || (i == 9);
            always @(posedge clk) begin
                if (rst) r <= 32'd0;
                else if (hit) begin
                    if (ld_be[0]) r[7:0]   <= ld_data[7:0];
                    if (ld_be[1]) r[15:8]  <= ld_data[15:8];
                    if (ld_be[2] && !narrow) r[23:16] <= ld_data[23:16];
                    if (ld_be[3] && !narrow) r[31:24] <= ld_data[31:24];
                end
            end
            assign rf[i*32 +: 32] = r;
        end
    endgenerate

    // The halftone pattern (16 rows of 16 bits, two rows a word) in LUTRAM rather than 256 flops
    // and a 256:1 mux. LUTRAM has no reset, so a byte reads through its flag: nz[k] is "byte k
    // was last loaded non-zero", cleared at reset as the flops were, and a byte whose flag is
    // clear reads 0. The flags are also the sniff (any byte non-zero) without a 256-input OR.
    // byte k (row k/2, bits (k%2)*8 .. +7) is lane k%4 of word k/4: one 8-deep memory a lane
    reg [31:0] nz;
    wire ht_hit = ld_we && ld_word[4:3] == 2'b10;
    wire [7:0] lane [0:3];
    genvar k;
    generate
        for (k = 0; k < 4; k = k + 1) begin : hb
            reg [7:0] m [0:7];
            always @(posedge clk)
                if (ht_hit && ld_be[k]) m[ld_word[2:0]] <= ld_data[8*k +: 8];
            assign lane[k] = m[ht_y[3:1]];
        end
    endgenerate
    integer b;
    always @(posedge clk)
        for (b = 0; b < 32; b = b + 1)
            if (rst) nz[b] <= 1'b0;
            else if (ht_hit && ld_word[2:0] == b[4:2] && ld_be[b % 4]) nz[b] <= ld_data[8*(b%4) +: 8] != 8'd0;
    wire [4:0] lo = {ht_y, 1'b0}, hi = {ht_y, 1'b1};
    assign ht_row = {nz[hi] ? lane[hi[1:0]] : 8'd0, nz[lo] ? lane[lo[1:0]] : 8'd0};
    assign ht_nz = nz != 32'd0;

    always @(posedge clk) begin
        kick <= !rst && go && !busy && !kick;  // a kick while busy: the firmware never sends one
        if (go) kick_data <= cpu_wdata;
        if (rst || kick) coll <= 1'b0;
        else if (coll_hit) coll <= 1'b1;
        if (rst || kick) cycles <= 32'd0;
        else if (cyc_we) cycles <= cycles + cyc_val;
    end

    // Only STATUS and CYCLES are read. Everything else lives in the region memory the CPU's
    // writes were snooped from, as with the video registers.
    assign cpu_rdata = cpu_raddr == 5'd24 ? cycles : cpu_raddr == 5'd0 ? {busy || kick, 15'd0, dbg}
        : cpu_raddr == 5'd25 ? {15'd0, coll, 16'd0} : 32'd0;   // word 25: BLIT_COLL's byte (0xE6)
endmodule
