// The blitter register block (memmap BLIT_*, region offsets 0x80..0xDF), written the way
// the CPU writes the machine region: a word index, byte enables, a 32-bit word. A store of
// COMMAND with a non-zero byte is a KICK (the Zig machine runs the op on hwBlit() after the
// same register writes); its upper 24 bits carry a QUEUE's range (zm_blit_q.v).
//
// Two banks, so a store is never dropped:
// - the TAP bank, written by every store at any time, is memory's block (a LUT RAM: 24 words
//   in four byte lanes, read a word at a time);
// - the OP bank, the flops the engine reads (`rf`), is loaded only by the sequencer
//   (zm_blit_q): the tap bank copied word by word at a kick, then a QUEUE's descriptor words.
// While an op runs the cart may store the next op's registers: they wait in the tap bank.
//
// `rf` is the OP bank flattened, little-endian: word w = rf[w*32 +: 32]. The stride words
// keep their low 16 bits only (the Zig layout leaves the rest unused). CYCLES restarts at
// each kick and adds every op's cost: one op's, or a QUEUE's sum. STATUS (bit 31 BUSY) and
// CYCLES are the only words read back.
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
    output reg          kick,            // one clock: COMMAND was written non-zero
    output reg  [31:0]  kick_data,       // that store's word: COMMAND in [7:0]
    input  wire [4:0]   t_raddr,         // the tap bank, read by the sequencer
    output wire [31:0]  t_rdata,
    input  wire         ld_we,           // the op bank's one write port (the sequencer)
    input  wire [4:0]   ld_word,
    input  wire [3:0]   ld_be,
    input  wire [31:0]  ld_data,
    output wire [767:0] rf
);
    reg [31:0] cycles;
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
        for (i = 0; i < 24; i = i + 1) begin : g
            reg [31:0] r;
            wire hit = ld_we && ld_word == i;
            wire narrow = (i == 3) || (i == 5) || (i == 7) || (i == 9);
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

    always @(posedge clk) begin
        kick <= !rst && go && !busy && !kick;  // a kick while busy: the firmware never sends one
        if (go) kick_data <= cpu_wdata;
        if (rst || kick) cycles <= 32'd0;
        else if (cyc_we) cycles <= cycles + cyc_val;
    end

    // Only STATUS and CYCLES are read. Everything else lives in the region memory the CPU's
    // writes were snooped from, as with the video registers.
    assign cpu_rdata = cpu_raddr == 5'd24 ? cycles : cpu_raddr == 5'd0 ? {busy || kick, 15'd0, dbg} : 32'd0;
endmodule
