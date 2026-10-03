// The glass's register block: the ARM's view of the console, over the PS's
// M_AXI_GP0 (docs/FPGA_GLASS.md). The map is fpga/glass/src/map.zig, through
// gen/glass_map.vh.
//
// The slave speaks AXI3 as the GP port does, but takes single beats only: the
// ARM program maps the block uncached and makes 32-bit accesses, which the PS
// sends as one beat each. IDs are echoed, RLAST is always set, and every
// response is OKAY: an unmapped or read-only address is ignored on write and
// reads 0, so a stray access can never fault the ARM's menu.
//
// AW and W may arrive in either order or together; the write lands when both
// are held, and the next one is taken once B has been accepted.
//
// The cart CPU's side (its firmware, through LiteX CSRs): it pops key events,
// reads JOY and the pointer (zm_glass_ptr.v), and reports its state and a
// heartbeat that the ARM watches.
`default_nettype none

module zm_glass_regs (
    input  wire        clk,
    input  wire        rst,
    // AXI3 slave, single beats
    input  wire        s_awvalid,
    output wire        s_awready,
    input  wire [15:0] s_awaddr,
    input  wire [11:0] s_awid,
    input  wire        s_wvalid,
    output wire        s_wready,
    input  wire [31:0] s_wdata,
    input  wire [3:0]  s_wstrb,
    output reg         s_bvalid,
    input  wire        s_bready,
    output reg  [11:0] s_bid,
    output wire [1:0]  s_bresp,
    input  wire        s_arvalid,
    output wire        s_arready,
    input  wire [15:0] s_araddr,
    input  wire [11:0] s_arid,
    output reg         s_rvalid,
    input  wire        s_rready,
    output reg  [31:0] s_rdata,
    output reg  [11:0] s_rid,
    output wire [1:0]  s_rresp,
    output wire        s_rlast,
    // to the console
    output wire        cpu_run,            // 0 holds the cart CPU in reset
    output wire        osd_en,
    output reg  [23:0] osd_fg,
    output reg  [23:0] osd_bg,
    output reg  [31:0] load_base,
    output reg  [31:0] load_size,
    output reg  [7:0]  joy,
    output reg         osd_we,             // one character into the OSD text
    output reg  [8:0]  osd_waddr,
    output reg  [8:0]  osd_wdata,
    // the cart CPU's side
    output wire        key_valid,
    output wire [31:0] key_data,           // the oldest event, while key_valid
    input  wire        key_pop,
    input  wire        cart_state_we,
    input  wire [31:0] cart_state_in,
    input  wire        cart_beat_we,
    input  wire [31:0] cart_beat_in,
    output wire [31:0] ptr,                // the mouse, as the cart reads it
    input  wire        ptr_ack,
    input  wire [7:0]  ptr_ack_seq
);
`include "glass_map.vh"

    reg [31:0] ctrl, cart_state, cart_beat, scratch;
    assign cpu_run = ctrl[0];
    assign osd_en = ctrl[1];
    assign s_bresp = 2'b00;
    assign s_rresp = 2'b00;
    assign s_rlast = 1'b1;

    // --- the key FIFO: KEY_DEPTH entries, pushed by the ARM, popped by the cart
    localparam integer KD = ZG_KEY_DEPTH;
    reg [31:0] fifo [0:KD - 1];
    reg [3:0]  rd, wr;
    reg [4:0]  level;
    reg        overflow;
    assign key_valid = level != 5'd0;
    assign key_data = fifo[rd];
    wire full = level == KD[4:0];

    // --- write channel: hold AW and W until both are here
    reg        aw_have, w_have;
    reg [15:0] aw_addr;
    reg [31:0] w_data;
    reg [3:0]  w_strb;
    assign s_awready = !aw_have && !s_bvalid;
    assign s_wready = !w_have && !s_bvalid;
    wire       aw_now = aw_have || (s_awvalid && s_awready);
    wire       w_now = w_have || (s_wvalid && s_wready);
    wire [15:0] waddr = aw_have ? aw_addr : s_awaddr;
    wire [31:0] wdata = w_have ? w_data : s_wdata;
    wire [3:0]  wstrb = w_have ? w_strb : s_wstrb;
    wire       do_write = aw_now && w_now && !s_bvalid && wstrb != 4'd0;
    wire       wr_done = aw_now && w_now && !s_bvalid;
    wire       is_reg = waddr[15:12] == 4'd0;
    wire       push = do_write && is_reg && waddr[11:2] == ZG_REG_KEY_PUSH[11:2];
    wire       flush = do_write && is_reg && waddr[11:2] == ZG_REG_CTRL[11:2] && wdata[2];
    wire       pop = key_pop && key_valid;
    wire       ptr_we = do_write && is_reg && waddr[11:2] == ZG_REG_POINTER[11:2];

    zm_glass_ptr pointer (
        .clk(clk), .rst(rst), .we(ptr_we), .wdata(wdata[23:0]),
        .ack(ptr_ack), .ack_seq(ptr_ack_seq), .ptr(ptr)
    );

    always @(posedge clk) begin
        if (rst) begin
            {aw_have, w_have, s_bvalid} <= 3'b000;
        end else begin
            if (s_awvalid && s_awready && !wr_done) {aw_have, aw_addr} <= {1'b1, s_awaddr};
            if (s_awvalid && s_awready) s_bid <= s_awid;
            if (s_wvalid && s_wready && !wr_done) {w_have, w_data, w_strb} <= {1'b1, s_wdata, s_wstrb};
            if (wr_done) {aw_have, w_have, s_bvalid} <= 3'b001;
            else if (s_bvalid && s_bready) s_bvalid <= 1'b0;
        end
    end

    always @(posedge clk) begin
        osd_we <= do_write && waddr[15:12] == ZG_OFF_OSD_TEXT[15:12] && waddr[11:2] < ZG_OSD_CHARS[9:0];
        osd_waddr <= waddr[10:2];
        osd_wdata <= wdata[8:0];
        if (rst) begin
            ctrl <= 32'd0;
            {osd_fg, osd_bg} <= {24'hFFFFFF, 24'h000000};
            {load_base, load_size, joy, scratch} <= {ZG_DDR_CART_BASE, 32'd0, 8'd0, 32'd0};
        end else if (do_write && is_reg) begin
            case (waddr[11:2])
                ZG_REG_CTRL[11:2]:      ctrl <= wdata & 32'h3;
                ZG_REG_LOAD_BASE[11:2]: load_base <= wdata;
                ZG_REG_LOAD_SIZE[11:2]: load_size <= wdata;
                ZG_REG_JOY[11:2]:       joy <= wdata[7:0];
                ZG_REG_OSD_FG[11:2]:    osd_fg <= wdata[23:0];
                ZG_REG_OSD_BG[11:2]:    osd_bg <= wdata[23:0];
                ZG_REG_SCRATCH[11:2]:   scratch <= wdata;
                default: ;
            endcase
        end
    end

    always @(posedge clk) begin
        if (rst || flush) begin
            {rd, wr, level, overflow} <= 14'd0;
        end else begin
            if (push && !full) begin
                fifo[wr] <= wdata;
                wr <= wr + 4'd1;
            end
            if (push && full) overflow <= 1'b1;
            if (pop) rd <= rd + 4'd1;
            level <= level + {4'd0, push && !full} - {4'd0, pop};
        end
        // The cart CPU's reports; a CPU held in reset has nothing to report.
        if (rst || !cpu_run) {cart_state, cart_beat} <= 64'd0;
        else begin
            if (cart_state_we) cart_state <= cart_state_in;
            if (cart_beat_we) cart_beat <= cart_beat_in;
        end
    end

    // --- read channel: one beat, answered the clock after the address
    assign s_arready = !s_rvalid;
    wire [31:0] status = {29'd0, overflow, full, cpu_run};
    reg  [31:0] rmux;
    always @(*) begin
        case (s_araddr[11:2])
            ZG_REG_ID[11:2]:         rmux = ZG_ID_VALUE;
            ZG_REG_VERSION[11:2]:    rmux = ZG_VERSION;
            ZG_REG_CTRL[11:2]:       rmux = ctrl;
            ZG_REG_STATUS[11:2]:     rmux = status;
            ZG_REG_CART_STATE[11:2]: rmux = cart_state;
            ZG_REG_CART_BEAT[11:2]:  rmux = cart_beat;
            ZG_REG_LOAD_BASE[11:2]:  rmux = load_base;
            ZG_REG_LOAD_SIZE[11:2]:  rmux = load_size;
            ZG_REG_KEY_LEVEL[11:2]:  rmux = {27'd0, level};
            ZG_REG_JOY[11:2]:        rmux = {24'd0, joy};
            ZG_REG_OSD_FG[11:2]:     rmux = {8'd0, osd_fg};
            ZG_REG_OSD_BG[11:2]:     rmux = {8'd0, osd_bg};
            ZG_REG_SCRATCH[11:2]:    rmux = scratch;
            ZG_REG_POINTER[11:2]:    rmux = ptr;
            default:                 rmux = 32'd0;
        endcase
        if (s_araddr[15:12] != 4'd0) rmux = 32'd0;
    end
    always @(posedge clk) begin
        if (rst) s_rvalid <= 1'b0;
        else if (s_arvalid && s_arready) {s_rvalid, s_rdata, s_rid} <= {1'b1, rmux, s_arid};
        else if (s_rvalid && s_rready) s_rvalid <= 1'b0;
    end
endmodule

`default_nettype wire
