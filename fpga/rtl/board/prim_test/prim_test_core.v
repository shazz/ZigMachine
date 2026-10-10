// The primitive self-test (rtl/board/prim_test_top.v): one lane per primitive
// and mode the SoC's netlist uses, every lane checking itself, the results on
// GP0. Everything but the PS7 and the clock buffer, simulated whole by
// tests/tb/prim_test_tb.cpp. Map (byte offsets from 0x43C0_0000):
//   0x000 ID 0x5052494D "PRIM"
//   0x004 CTRL: write bit0 = restart (clears the results), bit1 = LOOP (run again
//         and again, accumulating); reads {LOOP, BUSY}
//   0x008/0x00C PASS (bit i: lane i passed)   0x010/0x014 DONE
//   0x018 lane count   0x01C runs completed   0x020 the current run's seed
//   0x800 + 32*i lane i: STATUS {done, pass, 22'b0, i}, ERRORS, FIRST_IDX, FIRST_GOT,
//         BAD[31:0], BAD[63:32], BAD[95:64], CHECKS  (prim_check.v)
// The lanes are prim_test_lanes.v.
`default_nettype none

module prim_test_core #(
    parameter integer BREAK_TEST = -1,  // a lane whose reference has bit 0 inverted (break tests)
    parameter [31:0]  SEED0 = 32'hACE1_2345
) (
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
    output wire        s_bvalid,
    input  wire        s_bready,
    output wire [11:0] s_bid,
    input  wire        s_arvalid,
    output wire        s_arready,
    input  wire [11:0] s_araddr,
    input  wire [11:0] s_arid,
    output wire        s_rvalid,
    input  wire        s_rready,
    output wire [31:0] s_rdata,
    output wire [11:0] s_rid,
    output wire        all_pass,
    output wire        busy_o
);
    localparam integer NL = 45;
    wire [NL-1:0]     done;
    wire [NL*224-1:0] res;
    reg               start = 1'b0, clear = 1'b0, started = 1'b0, busy = 1'b0, loop = 1'b0;
    reg  [31:0]       seed = SEED0, runs = 32'd0;
    prim_test_lanes #(.BREAK_TEST(BREAK_TEST), .NL(NL)) lanes (
        .clk(clk), .start(start), .clear(clear), .seed(seed), .done(done), .res(res)
    );

    // --- the GP0 side
    wire        wr;
    wire [11:0] waddr, raddr;
    wire [31:0] wdata;
    reg  [31:0] rword;
    prim_axi u_axi (
        .clk(clk), .rst(rst),
        .s_awvalid(s_awvalid), .s_awready(s_awready), .s_awaddr(s_awaddr), .s_awid(s_awid),
        .s_wvalid(s_wvalid), .s_wready(s_wready), .s_wdata(s_wdata), .s_wstrb(s_wstrb),
        .s_bvalid(s_bvalid), .s_bready(s_bready), .s_bid(s_bid),
        .s_arvalid(s_arvalid), .s_arready(s_arready), .s_araddr(s_araddr), .s_arid(s_arid),
        .s_rvalid(s_rvalid), .s_rready(s_rready), .s_rdata(s_rdata), .s_rid(s_rid),
        .wr(wr), .waddr(waddr), .wdata(wdata), .raddr(raddr), .rword(rword)
    );

    // --- start, restart, loop
    wire all_done = &done;
    always @(posedge clk) begin
        {start, clear} <= 2'b00;
        if (rst) begin
            {started, busy, loop, runs, seed} <= {3'b000, 32'd0, SEED0};
        end else if (!started) begin
            {started, start, clear} <= 3'b111;
        end else if (wr && waddr[11:2] == 10'd1) begin
            loop <= wdata[1];
            if (wdata[0]) {start, clear, runs, seed} <= {2'b11, 32'd0, seed + 32'h9E37_79B9};
        end else if (start) begin
            busy <= 1'b1;
        end else if (busy && all_done) begin
            {busy, runs} <= {1'b0, runs + 32'd1};
            if (loop) {start, seed} <= {1'b1, seed + 32'h9E37_79B9};
        end
    end

    // --- results: each lane's word for raddr[4:2], then the lane's (an AND-OR:
    // half the LUTs of an indexed part-select here)
    wire [63:0]      pass;
    wire [NL*32-1:0] lw;
    genvar i;
    generate
        for (i = 0; i < 64; i = i + 1) begin : slot
            if (i < NL) begin : lane
                localparam [7:0] ID = i;
                wire [223:0] r = res[i*224 +: 224];
                reg  [31:0]  w;
                assign pass[i] = done[i] && r[31:0] == 32'd0 && r[223:192] != 32'd0;
                always @(*)
                    case (raddr[4:2])
                        3'd0: w = {done[i], pass[i], 22'd0, ID};
                        3'd1: w = r[31:0];
                        3'd2: w = r[63:32];
                        3'd3: w = r[95:64];
                        3'd4: w = r[127:96];
                        3'd5: w = r[159:128];
                        3'd6: w = r[191:160];
                        default: w = r[223:192];
                    endcase
                assign lw[i*32 +: 32] = w;
            end else begin : none
                assign pass[i] = 1'b0;
            end
        end
    endgenerate
    reg [31:0] lane_word;
    integer n;
    always @(*) begin
        lane_word = 32'd0;
        for (n = 0; n < NL; n = n + 1)
            lane_word = lane_word | (lw[n*32 +: 32] & {32{raddr[10:5] == n}});
    end
    wire [63:0] dmask = {{(64 - NL){1'b0}}, done};
    assign all_pass = pass[NL-1:0] == {NL{1'b1}};
    assign busy_o = busy;

    always @(*)
        if (raddr[11]) rword = lane_word;
        else case (raddr[10:2])
            9'd0: rword = 32'h5052_494D;
            9'd1: rword = {30'd0, loop, busy};
            9'd2: rword = pass[31:0];
            9'd3: rword = pass[63:32];
            9'd4: rword = dmask[31:0];
            9'd5: rword = dmask[63:32];
            9'd6: rword = NL;
            9'd7: rword = runs;
            9'd8: rword = seed;
            default: rword = 32'd0;
        endcase
endmodule

`default_nettype wire
