// The blitter register block (memmap BLIT_*, region offsets 0x80..0xE3), written the way
// the CPU writes the machine region: a word index, byte enables, a 32-bit word. Writing
// COMMAND with a non-zero byte starts the op (the Zig machine runs it on hwBlit() after
// the same register writes); register writes while an op runs are dropped, so the
// engine reads live registers. STATUS (bit 7 BUSY) and CYCLES are read-only.
//
// `rf` is the 24 stored words flattened, little-endian: word w = rf[w*32 +: 32]. The
// stride words keep their low 16 bits only (the Zig layout leaves the rest unused).
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
    output wire [767:0] rf
);
    reg [31:0] cycles;
    wire wr_ok = cpu_we && !busy && !start;

    genvar i;
    generate
        for (i = 0; i < 24; i = i + 1) begin : g
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

    always @(posedge clk) begin
        start <= !rst && wr_ok && cpu_waddr == 5'd0 && cpu_be[0] && cpu_wdata[7:0] != 8'd0;
        if (rst) cycles <= 32'd0;
        else if (cyc_we) cycles <= cyc_val;
    end

    // Only the block's two write-backs are read: STATUS and CYCLES. Everything else lives in the
    // region memory the CPU's writes were snooped from, as with the video registers.
    assign cpu_rdata = cpu_raddr == 5'd24 ? cycles : cpu_raddr == 5'd0 ? {busy || start, 15'd0, dbg} : 32'd0;
endmodule
