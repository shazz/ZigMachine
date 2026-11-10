// The glass's register block: the ARM's view of the console, over the PS's M_AXI_GP0
// (docs/FPGA_GLASS.md). The map is fpga/glass/src/map.zig, through gen/glass_map.vh.
//
// AXI3 as the GP port speaks it, single beats only (the ARM maps the block uncached,
// 32-bit accesses). IDs are echoed, RLAST is always set, and every response is OKAY:
// an unmapped or read-only address is ignored on write and reads 0, so a stray access
// can never fault the menu. AW and W may come in either order or together; the next
// write is taken once B is accepted.
// The cart CPU's side (LiteX CSRs): it pops key events, reads JOY, the pointer
// (zm_glass_ptr.v) and CTRL.WARM at boot, and reports a state and a heartbeat.
// AUDIO_VOL goes to the audio mixer (FPGA_GLASS.md, "Volume"); OSD_* to zm_glass_osd.
// OFF_ASTRO's page goes to ASTROLABE's mailbox (zm_astro_mbox.v, SPIKE): writes through, reads
// answered a clock later than a register's (the block RAM's read), so every read takes two clocks.
`default_nettype none

module zm_glass_regs #(
    parameter [31:0] CTRL_INIT = 32'd0  // after reset; rtl/board/osd_test_top.v starts with CTRL_OSD
) (
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
    output wire        osd_en, osd_stats,  // CTRL_OSD, CTRL_OSD_STATS
    output reg  [10:0] osd_x0,             // REG_OSD_POS: the window's top-left
    output reg  [9:0]  osd_y0,
    output reg  [23:0] osd_fg,
    output reg  [23:0] osd_bg,
    output reg  [31:0] load_base,
    output reg  [31:0] load_size,
    output reg  [7:0]  joy,
    output wire        boot_warm,          // CTRL.WARM: the firmware's next boot keeps the cart's memory
    output reg  [8:0]  audio_vol,          // {mute, volume 0..255}, to the audio mixer
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
    input  wire [7:0]  ptr_ack_seq,
    // ASTROLABE's mailbox (zm_astro_mbox.v port B): word addresses in OFF_ASTRO's 4 KiB page
    output wire        mb_we, mb_re,
    output wire [9:0]  mb_waddr, mb_raddr,
    output wire [31:0] mb_wdata,
    output wire [3:0]  mb_wstrb,
    input  wire [31:0] mb_rdata
);
`include "glass_map.vh"

    reg [31:0] ctrl, cart_state, cart_beat, scratch;
    assign {osd_stats, boot_warm, osd_en, cpu_run} = {ctrl[4], ctrl[3], ctrl[1], ctrl[0]};
    assign s_bresp = 2'b00, s_rresp = 2'b00, s_rlast = 1'b1;

    wire [4:0] level;  // the key FIFO's (zm_glass_keys.v)
    wire       full, overflow;

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
    wire       ptr_we = do_write && is_reg && waddr[11:2] == ZG_REG_POINTER[11:2];

    assign {mb_waddr, mb_wdata, mb_wstrb} = {waddr[11:2], wdata, wstrb};
    assign mb_we = do_write && waddr[15:12] == ZG_OFF_ASTRO[15:12];

    // the key FIFO: KEY_DEPTH entries, pushed by the ARM, popped by the cart
    zm_glass_keys #(.KD(ZG_KEY_DEPTH)) keys (
        .clk(clk), .rst(rst), .flush(flush), .push(push), .wdata(wdata), .pop_req(key_pop),
        .key_valid(key_valid), .key_data(key_data), .level(level), .full(full), .overflow(overflow)
    );

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
            ctrl <= CTRL_INIT;
            {osd_fg, osd_bg, osd_x0, osd_y0} <= {24'hFFFFFF, 24'h000000, ZG_OSD_X0[10:0], ZG_OSD_Y0[9:0]};
            {load_base, load_size, joy, scratch} <= {ZG_LOAD_BASE_RESET, 32'd0, 8'd0, 32'd0};
            audio_vol <= ZG_AUDIO_VOL_RESET[8:0];
        end else if (do_write && is_reg) begin
            case (waddr[11:2])
                ZG_REG_CTRL[11:2]:      ctrl <= wdata & (ZG_CTRL_RUN | ZG_CTRL_OSD | ZG_CTRL_WARM | ZG_CTRL_OSD_STATS);
                ZG_REG_LOAD_BASE[11:2]: load_base <= wdata;
                ZG_REG_LOAD_SIZE[11:2]: load_size <= wdata;
                ZG_REG_JOY[11:2]:       joy <= wdata[7:0];
                ZG_REG_OSD_FG[11:2]:    osd_fg <= wdata[23:0];
                ZG_REG_OSD_BG[11:2]:    osd_bg <= wdata[23:0];
                ZG_REG_SCRATCH[11:2]:   scratch <= wdata;
                ZG_REG_AUDIO_VOL[11:2]: audio_vol <= wdata[8:0];
                ZG_REG_OSD_POS[11:2]:   {osd_y0, osd_x0} <= {wdata[25:16], wdata[10:0]};
                default: ;
            endcase
        end
    end

    always @(posedge clk) begin
        // The cart CPU's reports; a CPU held in reset has nothing to report.
        if (rst || !cpu_run) {cart_state, cart_beat} <= 64'd0;
        else begin
            if (cart_state_we) cart_state <= cart_state_in;
            if (cart_beat_we) cart_beat <= cart_beat_in;
        end
    end

    // --- read channel: one beat. The address is taken, then a register is answered the next
    // clock; a mailbox word is read the next clock (unless a mailbox write holds the RAM's port)
    // and answered the one after.
    reg        r_busy, r_mb, r_wait;
    reg [15:0] r_addr;
    assign s_arready = !r_busy;
    assign mb_raddr = r_addr[11:2];
    assign mb_re = r_busy && r_mb && !r_wait && !s_rvalid && !mb_we;
    wire [31:0] status = {29'd0, overflow, full, cpu_run};
    reg  [31:0] rmux;
    always @(*) begin
        case (r_addr[11:2])
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
            ZG_REG_AUDIO_VOL[11:2]:  rmux = {23'd0, audio_vol};
            ZG_REG_OSD_POS[11:2]:    rmux = {6'd0, osd_y0, 5'd0, osd_x0};
            default:                 rmux = 32'd0;
        endcase
        if (r_addr[15:12] != 4'd0) rmux = 32'd0;
    end
    always @(posedge clk) begin
        if (rst) {r_busy, r_wait, s_rvalid} <= 3'b000;
        else if (s_arvalid && s_arready)
            {r_busy, r_mb, r_wait, r_addr, s_rid} <= {1'b1, s_araddr[15:12] == ZG_OFF_ASTRO[15:12], 1'b0, s_araddr, s_arid};
        else if (s_rvalid) begin
            if (s_rready) {s_rvalid, r_busy} <= 2'b00;
        end else if (r_wait) {s_rvalid, s_rdata, r_wait} <= {1'b1, mb_rdata, 1'b0};
        else if (r_busy && !r_mb) {s_rvalid, s_rdata} <= {1'b1, rmux};
        else if (mb_re) r_wait <= 1'b1;
    end
endmodule

`default_nettype wire
