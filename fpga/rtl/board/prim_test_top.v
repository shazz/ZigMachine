// The primitive self-test bitstream (`make prim-test`): every primitive and mode
// the board SoC's netlist uses, each writing an LFSR pattern, reading it back
// and comparing it with a reference built in the fabric, the results on the
// PS's M_AXI_GP0 at 0x43C0_0000 for U-Boot (tools/prim_test_read.py,
// boards/microphase_z7_7010/README.md "prim-test"). openXC7 wrote a wrong
// bitstream twice for a mode that simulates right (docs/FPGA_STEPS.md
// "2026-10-04"); this design shows such a mode in minutes, and the modes it
// proves go into fpga/silicon_prims.json (tools/prim_allowlist.py).
//
// Everything but the PS7 is rtl/board/prim_test/prim_test_core.v, simulated by
// tests/tb/prim_test_tb.cpp. The tests run once at power-on (about 3 ms) and
// again on each CTRL write.
//
// Clock: PL_CLK_50M straight (Yosys gives it a BUFG), also MAXIGP0ACLK, so the
// GP0 slave works without FCLK0 and answers every single-beat access.
// Not covered: ODDR (it only drives a pad, and no board wire loops one back;
// the HDMI bitstreams prove it), the PLL (the same), the PS7 itself.
// LEDs (active low): PL_LED1 lit once every lane has passed; PL_LED2 blinks
// (about 1.5 Hz) while the design runs, fast while a run is in progress.
`default_nettype none

module prim_test_top (
    input  wire PL_CLK_50M,
    output wire PL_LED1,
    output wire PL_LED2
);
    wire clk = PL_CLK_50M;
    reg  [7:0] por = 8'd0;
    always @(posedge clk) if (!por[7]) por <= por + 8'd1;
    wire rst = !por[7];

    wire        awvalid, awready, wvalid, wready, bvalid, bready, arvalid, arready, rvalid, rready;
    wire [31:0] awaddr, araddr, wdata, rdata;
    wire [11:0] awid, arid, bid, rid;
    wire [3:0]  wstrb;
    PS7 u_ps7 (
        .MAXIGP0ACLK(clk),
        .MAXIGP0AWVALID(awvalid), .MAXIGP0AWREADY(awready), .MAXIGP0AWADDR(awaddr), .MAXIGP0AWID(awid),
        .MAXIGP0WVALID(wvalid), .MAXIGP0WREADY(wready), .MAXIGP0WDATA(wdata), .MAXIGP0WSTRB(wstrb),
        .MAXIGP0BVALID(bvalid), .MAXIGP0BREADY(bready), .MAXIGP0BID(bid), .MAXIGP0BRESP(2'b00),
        .MAXIGP0ARVALID(arvalid), .MAXIGP0ARREADY(arready), .MAXIGP0ARADDR(araddr), .MAXIGP0ARID(arid),
        .MAXIGP0RVALID(rvalid), .MAXIGP0RREADY(rready), .MAXIGP0RDATA(rdata), .MAXIGP0RID(rid),
        .MAXIGP0RRESP(2'b00), .MAXIGP0RLAST(1'b1)
    );

    wire all_pass, busy;
    prim_test_core u_core (
        .clk(clk), .rst(rst),
        .s_awvalid(awvalid), .s_awready(awready), .s_awaddr(awaddr[11:0]), .s_awid(awid),
        .s_wvalid(wvalid), .s_wready(wready), .s_wdata(wdata), .s_wstrb(wstrb),
        .s_bvalid(bvalid), .s_bready(bready), .s_bid(bid),
        .s_arvalid(arvalid), .s_arready(arready), .s_araddr(araddr[11:0]), .s_arid(arid),
        .s_rvalid(rvalid), .s_rready(rready), .s_rdata(rdata), .s_rid(rid),
        .all_pass(all_pass), .busy_o(busy)
    );

    reg [24:0] blink = 25'd0;
    always @(posedge clk) blink <= blink + 25'd1;
    assign PL_LED1 = ~all_pass;
    assign PL_LED2 = ~(busy ? blink[20] : blink[24]);
endmodule

`default_nettype wire
