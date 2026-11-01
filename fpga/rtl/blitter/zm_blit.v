// The ZigMachine blitter as a standalone block: the register block (the way the CPU
// writes the machine region), the sequencer that loads the engine's registers from it or
// from a QUEUE's descriptors (zm_blit_q), and the engine, behind a memory master with
// separate read and write ports. Addresses are the machine's linear byte addresses (the video region is
// ZM_HW_VIDEO_BASE + offset); the SoC adds its own base the way it does for the video DMA.
// See docs/BLITTER_HW_SPEC.md "FPGA implementation".
`default_nettype none

module zm_blit (
    input  wire         clk,
    input  wire         rst,
    // register port: word index in the block (byte offset from OFF_BLIT / 4), byte enables
    input  wire         cpu_we,
    input  wire [4:0]   cpu_waddr,
    input  wire [3:0]   cpu_be,
    input  wire [31:0]  cpu_wdata,
    input  wire [4:0]   cpu_raddr,
    output wire [31:0]  cpu_rdata,
    output wire         busy,
    output wire         copying,         // a kick is copying the block: no register store may arrive now
    // the QUEUE ring (memmap OFF_BLIT_QUEUE): the CPU's stores to it, by word index
    input  wire         q_we,
    input  wire [8:0]   q_waddr,
    input  wire [3:0]   q_be,
    input  wire [31:0]  q_wdata,
    // memory read: a request, then its word at least one clock later (in order)
    output wire         rd_req_valid,
    input  wire         rd_req_ready,
    output wire [31:0]  rd_req_addr,
    input  wire         rd_rsp_valid,
    input  wire [31:0]  rd_rsp_data,
    // memory write: address (byte), data lane + strobe; wr_pending high until the memory has landed them
    output wire         wr_req_valid,
    input  wire         wr_req_ready,
    output wire [31:0]  wr_req_addr,
    output wire [31:0]  wr_req_data,
    output wire [3:0]   wr_req_strb,
    input  wire         wr_pending
);
    wire [511:0] rf;
    wire [3:0] ht_y;
    wire [15:0] ht_row;
    wire ht_nz;
    wire kick, ld_we, core_start, cyc_we, core_busy, q_busy, q_copying, coll_hit;
    wire [4:0] t_raddr, ld_word;
    wire [3:0] ld_be;
    wire [15:0] dbg;
    wire [31:0] cyc_val, kick_data, t_rdata, ld_data;
    zm_blit_regs regs (.clk(clk), .rst(rst), .cpu_we(cpu_we), .cpu_waddr(cpu_waddr), .cpu_be(cpu_be),
        .cpu_wdata(cpu_wdata), .cpu_raddr(cpu_raddr), .cpu_rdata(cpu_rdata), .busy(busy), .dbg(dbg),
        .cyc_we(cyc_we), .cyc_val(cyc_val), .coll_hit(coll_hit), .kick(kick), .kick_data(kick_data), .t_raddr(t_raddr),
        .t_rdata(t_rdata), .ld_we(ld_we), .ld_word(ld_word), .ld_be(ld_be), .ld_data(ld_data), .rf(rf), .ht_y(ht_y), .ht_row(ht_row), .ht_nz(ht_nz));
    zm_blit_q seq (.clk(clk), .rst(rst), .kick(kick), .kick_data(kick_data), .q_we(q_we), .q_waddr(q_waddr),
        .q_be(q_be), .q_wdata(q_wdata), .t_raddr(t_raddr), .t_rdata(t_rdata), .ld_we(ld_we), .ld_word(ld_word),
        .ld_be(ld_be), .ld_data(ld_data), .core_start(core_start), .core_busy(core_busy), .d_base(rf[287:256]), .busy(q_busy),
        .copying(q_copying));
    zm_blit_core core (.clk(clk), .rst(rst), .start(core_start), .rf(rf), .ht_y(ht_y), .ht_row(ht_row), .ht_nz(ht_nz), .busy(core_busy), .cyc_we(cyc_we),
        .cyc_val(cyc_val), .rd_req_valid(rd_req_valid), .rd_req_ready(rd_req_ready), .rd_req_addr(rd_req_addr),
        .rd_rsp_valid(rd_rsp_valid), .rd_rsp_data(rd_rsp_data), .wr_req_valid(wr_req_valid),
        .wr_req_ready(wr_req_ready), .wr_req_addr(wr_req_addr), .wr_req_data(wr_req_data),
        .wr_req_strb(wr_req_strb), .wr_pending(wr_pending), .coll_hit(coll_hit), .dbg(dbg));
    assign busy = core_busy || q_busy || kick;
    assign copying = kick || q_copying;
endmodule
