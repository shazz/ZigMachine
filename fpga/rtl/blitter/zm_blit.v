// The ZigMachine blitter as a standalone block: the register block (the way the CPU
// writes the machine region) and the engine, behind a memory master with separate read
// and write ports. Addresses are the machine's linear byte addresses (the video region is
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
    wire [767:0] rf;
    wire start, cyc_we, core_busy;
    wire [15:0] dbg;
    wire [31:0] cyc_val;
    zm_blit_regs regs (.clk(clk), .rst(rst), .cpu_we(cpu_we), .cpu_waddr(cpu_waddr), .cpu_be(cpu_be),
        .cpu_wdata(cpu_wdata), .cpu_raddr(cpu_raddr), .cpu_rdata(cpu_rdata), .busy(core_busy), .cyc_we(cyc_we),
        .cyc_val(cyc_val), .start(start), .rf(rf), .dbg(dbg));
    zm_blit_core core (.clk(clk), .rst(rst), .start(start), .rf(rf), .busy(core_busy), .cyc_we(cyc_we),
        .cyc_val(cyc_val), .rd_req_valid(rd_req_valid), .rd_req_ready(rd_req_ready), .rd_req_addr(rd_req_addr),
        .rd_rsp_valid(rd_rsp_valid), .rd_rsp_data(rd_rsp_data), .wr_req_valid(wr_req_valid),
        .wr_req_ready(wr_req_ready), .wr_req_addr(wr_req_addr), .wr_req_data(wr_req_data),
        .wr_req_strb(wr_req_strb), .wr_pending(wr_pending), .dbg(dbg));
    assign busy = core_busy || start;
endmodule
