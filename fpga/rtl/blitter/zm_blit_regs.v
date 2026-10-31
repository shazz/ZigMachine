// The blitter register block (memmap BLIT_*, region offsets 0x80..0xE3), written the way
// the CPU writes the machine region: a word index, byte enables, a 32-bit word. Writing
// COMMAND with a non-zero byte starts the op (the Zig machine runs it on hwBlit() after
// the same register writes); register writes while an op runs are dropped, so the
// engine reads live registers. STATUS (bit 7 BUSY) and CYCLES are read-only.
//
// `rf` is words 0..15 flattened, little-endian: word w = rf[w*32 +: 32] (the halftone, words
// 16..23, is in LUTRAM below). The stride words keep their low 16 bits only.
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
    input  wire         busy,            // an op is running
    input  wire [15:0]  dbg,             // STATUS[15:0], the engine's state (zm_blit_core dbg)
    input  wire         cyc_we,          // the engine stores CYCLES
    input  wire [31:0]  cyc_val,
    output reg          start,           // one clock: COMMAND was written non-zero
    output wire [511:0] rf,              // words 0..15; the halftone (words 16..23) is below
    input  wire [3:0]   ht_y,            // a halftone row, read combinationally
    output wire [15:0]  ht_row,
    output wire         ht_nz            // some halftone byte is not zero (the pre-1.5.0 sniff)
);
    reg [31:0] cycles;
    wire wr_ok = cpu_we && !busy && !start;

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : g
            reg [31:0] r;
            wire hit = wr_ok && cpu_waddr == i;
            wire narrow = (i == 3) || (i == 5) || (i == 7) || (i == 9);
            always @(posedge clk) begin
                if (rst) r <= 32'd0;
                else if (hit) begin
                    if (cpu_be[0]) r[7:0]   <= cpu_wdata[7:0];
                    if (cpu_be[1]) r[15:8]  <= cpu_wdata[15:8];
                    if (cpu_be[2] && !narrow) r[23:16] <= cpu_wdata[23:16];
                    if (cpu_be[3] && !narrow) r[31:24] <= cpu_wdata[31:24];
                end
            end
            assign rf[i*32 +: 32] = r;
        end
    endgenerate

    // The halftone pattern (16 rows of 16 bits, two rows a word) in LUTRAM rather than 256 flops
    // and a 256:1 mux. LUTRAM has no reset, so a byte reads through its flag: nz[k] is "byte k
    // was last written non-zero", cleared at reset as the flops were, and a byte whose flag is
    // clear reads 0. The flags are also the sniff (any byte non-zero) without a 256-input OR.
    // byte k (row k/2, bits (k%2)*8 .. +7) is lane k%4 of word k/4: one 8-deep memory a lane
    reg [31:0] nz;
    wire ht_hit = wr_ok && cpu_waddr[4:3] == 2'b10;
    wire [7:0] lane [0:3];
    genvar k;
    generate
        for (k = 0; k < 4; k = k + 1) begin : hb
            reg [7:0] m [0:7];
            always @(posedge clk)
                if (ht_hit && cpu_be[k]) m[cpu_waddr[2:0]] <= cpu_wdata[8*k +: 8];
            assign lane[k] = m[ht_y[3:1]];
        end
    endgenerate
    integer b;
    always @(posedge clk)
        for (b = 0; b < 32; b = b + 1)
            if (rst) nz[b] <= 1'b0;
            else if (ht_hit && cpu_waddr[2:0] == b[4:2] && cpu_be[b % 4]) nz[b] <= cpu_wdata[8*(b%4) +: 8] != 8'd0;
    wire [4:0] lo = {ht_y, 1'b0}, hi = {ht_y, 1'b1};
    assign ht_row = {nz[hi] ? lane[hi[1:0]] : 8'd0, nz[lo] ? lane[lo[1:0]] : 8'd0};
    assign ht_nz = nz != 32'd0;

    always @(posedge clk) begin
        start <= !rst && wr_ok && cpu_waddr == 5'd0 && cpu_be[0] && cpu_wdata[7:0] != 8'd0;
        if (rst) cycles <= 32'd0;
        else if (cyc_we) cycles <= cyc_val;
    end

    // Only the block's two write-backs are read: STATUS and CYCLES. Everything else lives in the
    // region memory the CPU's writes were snooped from, as with the video registers.
    assign cpu_rdata = cpu_raddr == 5'd24 ? cycles : cpu_raddr == 5'd0 ? {busy || start, 15'd0, dbg} : 32'd0;
endmodule
