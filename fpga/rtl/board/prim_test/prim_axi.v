// The primitive self-test's GP0 slave (rtl/board/prim_test_top.v): AXI3 single
// beats as the PS's M_AXI_GP0 makes them for a U-Boot md.l / mw.l. IDs echoed,
// RLAST always set, every response OKAY. Every PS7 pin meets a flip-flop first
// (nextpnr does not time the PS7's pins: docs/FPGA_STEPS.md "2026-10-04"), so a
// write lands one clock after both AW and W are held, and a read answers one
// clock after AR: `rword` is the word at `raddr`, looked up from a register.
`default_nettype none

module prim_axi (
    input  wire        clk,
    input  wire        rst,
    input  wire        s_awvalid,
    output wire        s_awready,
    input  wire [11:0] s_awaddr,
    input  wire [11:0] s_awid,
    input  wire        s_wvalid,
    output wire        s_wready,
    input  wire [31:0] s_wdata,
    input  wire [3:0]  s_wstrb,
    output reg         s_bvalid,
    input  wire        s_bready,
    output reg  [11:0] s_bid,
    input  wire        s_arvalid,
    output wire        s_arready,
    input  wire [11:0] s_araddr,
    input  wire [11:0] s_arid,
    output reg         s_rvalid,
    input  wire        s_rready,
    output reg  [31:0] s_rdata,
    output reg  [11:0] s_rid,
    output reg         wr,      // one clock: write wdata at waddr
    output reg  [11:0] waddr,
    output reg  [31:0] wdata,
    output reg  [11:0] raddr,
    input  wire [31:0] rword
);
    reg        aw_have, w_have, ar_have;
    reg [11:0] aw_addr;
    reg [31:0] w_data;
    reg [3:0]  w_strb;
    assign s_awready = !aw_have;
    assign s_wready = !w_have;
    assign s_arready = !ar_have && !s_rvalid;

    always @(posedge clk)
        if (rst) begin
            {aw_have, w_have, s_bvalid, wr} <= 4'd0;
        end else begin
            wr <= 1'b0;
            if (s_awvalid && !aw_have) {aw_have, aw_addr, s_bid} <= {1'b1, s_awaddr, s_awid};
            if (s_wvalid && !w_have) {w_have, w_data, w_strb} <= {1'b1, s_wdata, s_wstrb};
            if (aw_have && w_have && !s_bvalid) begin
                {wr, waddr, wdata} <= {w_strb != 4'd0, aw_addr, w_data};
                {aw_have, w_have, s_bvalid} <= 3'b001;
            end
            if (s_bvalid && s_bready) s_bvalid <= 1'b0;
        end

    always @(posedge clk)
        if (rst) begin
            {ar_have, s_rvalid} <= 2'd0;
        end else begin
            if (s_arvalid && s_arready) {ar_have, raddr, s_rid} <= {1'b1, s_araddr, s_arid};
            if (ar_have) {s_rvalid, s_rdata, ar_have} <= {1'b1, rword, 1'b0};
            if (s_rvalid && s_rready) s_rvalid <= 1'b0;
        end
endmodule

`default_nettype wire
