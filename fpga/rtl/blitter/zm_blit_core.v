// The blitter engine: decodes the register block, runs the checks (zm_blit_chk), starts the
// sequencer of the op (FILL, BLIT, LINE, TRIANGLE: each turns geometry into pixels) and
// feeds their pixels through the one pixel unit (zm_blit_px), which owns the memory ports
// and keeps many pixels in flight; DRAIN waits until the last is written and landed.
// CYCLES is the Zig machine's model: pixels written (BLIT, TRIANGLE), every step (LINE),
// W*H (FILL, clipped pixels included); 0 when the checks refuse the op.
//   IDLE -> CHK -> RUN (sequencer) -> DRAIN (pixel unit idle, writes landed) -> FIN -> IDLE
`default_nettype none
`include "memmap.vh"

module zm_blit_core (
    input  wire         clk,
    input  wire         rst,
    input  wire         start,
    input  wire [767:0] rf,
    output wire         busy,
    output wire         cyc_we,
    output wire [31:0]  cyc_val,
    output wire         rd_req_valid,
    input  wire         rd_req_ready,
    output wire [31:0]  rd_req_addr,
    input  wire         rd_rsp_valid,
    input  wire [31:0]  rd_rsp_data,
    output wire         wr_req_valid,
    input  wire         wr_req_ready,
    output wire [31:0]  wr_req_addr,
    output wire [31:0]  wr_req_data,
    output wire [3:0]   wr_req_strb,
    input  wire         wr_pending,
    output wire [15:0]  dbg              // STATUS[15:0]: where an op is stuck (cycles/bblit.c's timeout trap)
);
`include "zm_blit_fields.vh"
    localparam [2:0] IDLE = 0, CHK = 1, RUN = 2, DRAIN = 3, FIN = 4;
    reg [2:0] st;
    reg [7:0] op;
    reg [3:0] go;           // {TRIANGLE, LINE, FILL, BLIT}: a one-clock start
    reg [31:0] cost;
    assign busy = st != IDLE;
    assign cyc_we = st == FIN;
    assign cyc_val = cost;

    function signed [17:0] sx(input [15:0] v);
        sx = {{2{v[15]}}, v};
    endfunction
    wire [22:0] dlin = ZM_HW_VIDEO_BASE + f_d_base[22:0];
    wire abs_src = f_con2[0];
    wire [22:0] a_lin = abs_src ? f_a_base[22:0] : ZM_HW_VIDEO_BASE + f_a_base[22:0];
    wire [22:0] b_lin = abs_src ? f_b_base[22:0] : ZM_HW_VIDEO_BASE + f_b_base[22:0];
    wire ht_on = f_con2[2] || f_ht != 256'd0;
    wire fill_mt = f_con2[1];
    // Registered decodes and clip box: both are functions of registers that cannot change while
    // BUSY (writes are dropped), so a copy one clock behind is exact by the time CHK reads it: the
    // COMMAND store that starts an op comes at least a clock after the stores that set them up.
    // Without the copies the pixel unit's inputs were 11 to 15 logic levels from the register
    // block, -1.5 ns at 100 MHz on the board (Vivado, 2026-10-10).
    reg is_blit, is_fill, is_line;
    always @(posedge clk) begin
        is_blit <= op == ZM_BLIT_CMD_BLIT; is_fill <= op == ZM_BLIT_CMD_FILL; is_line <= op == ZM_BLIT_CMD_LINE;
    end

    wire signed [17:0] ccx0, ccy0, ccx1, ccy1, ex0, ey0, ex1, ey1;
    reg signed [17:0] cx0, cy0, cx1, cy1;
    zm_blit_clip clip (.con(f_con), .ds(f_d_stride), .clip_x(f_clip_x), .clip_y(f_clip_y),
        .clip_w(f_clip_w), .clip_h(f_clip_h), .x0(ccx0), .y0(ccy0), .x1(ccx1), .y1(ccy1));
    always @(posedge clk) {cx0, cy0, cx1, cy1} <= {ccx0, ccy0, ccx1, ccy1};
    wire chk_done, chk_ok, overlap;
    zm_blit_chk chk (.clk(clk), .go(start), .cmd(f_cmd), .use_a(f_con[0]), .use_b(f_con[1]), .abs_src(abs_src),
        .d_base(f_d_base), .a_base(f_a_base), .b_base(f_b_base), .ds(f_d_stride), .a_stride(f_a_stride),
        .b_stride(f_b_stride), .w(f_w), .h(f_h), .x0(sx(f_x0)), .y0(sx(f_y0)), .x1(sx(f_x1)), .y1(sx(f_y1)),
        .x2(sx(f_x2)), .y2(sx(f_y2)), .cx0(cx0), .cy0(cy0), .cx1(cx1), .cy1(cy1),
        .done(chk_done), .ok(chk_ok), .ex0(ex0), .ey0(ey0), .ex1(ex1), .ey1(ey1), .overlap(overlap));

    // The sequencers: each turns its op's geometry into pixels (x, y, B colour, minterm, channel flags).
    wire [3:0] hx_f, hy_f, hx_t, hy_t;
    wire ht_bit;
    zm_blit_htbit htb (.ht(f_ht), .x(is_fill ? hx_f : hx_t), .y(is_fill ? hy_f : hy_t), .bit_o(ht_bit));
    wire [3:0] v, sdone;     // sequencer px_valid / done, in the order of `go`: BLIT FILL LINE TRI
    wire signed [17:0] x_b, y_b, x_f, y_f, x_l, y_l, x_t, y_t;
    wire [7:0] bi_f, mt_f, bi_l, mt_l, bi_t, mt_t;
    wire [22:0] aaddr, baddr;
    wire px_ready, line_step;
    zm_blit_blit sb (.clk(clk), .rst(rst), .go(go[0]), .a_lin(a_lin), .b_lin(b_lin), .a_stride(f_a_stride),
        .b_stride(f_b_stride), .desc(f_con[6]), .x0(sx(f_x0)), .y0(sx(f_y0)), .ex0(ex0), .ey0(ey0),
        .ex1(ex1), .ey1(ey1), .px_valid(v[0]), .px_x(x_b), .px_y(y_b), .px_aaddr(aaddr), .px_baddr(baddr),
        .px_ready(px_ready), .done(sdone[0]));
    zm_blit_fill sf (.clk(clk), .rst(rst), .go(go[1]), .color(f_color), .bg(f_bg), .mt(f_mt), .fill_mt(fill_mt),
        .ht_on(ht_on), .ht_bit(ht_bit), .ex0(ex0), .ey0(ey0), .ex1(ex1), .ey1(ey1), .hx(hx_f), .hy(hy_f),
        .px_valid(v[1]), .px_x(x_f), .px_y(y_f), .px_bimm(bi_f), .px_mt(mt_f), .px_ready(px_ready), .done(sdone[1]));
    zm_blit_line sl (.clk(clk), .rst(rst), .go(go[2]), .color(f_color), .mt(f_mt), .x0(sx(f_x0)), .y0(sx(f_y0)),
        .x1(sx(f_x1)), .y1(sx(f_y1)), .cx0(cx0), .cy0(cy0), .cx1(cx1), .cy1(cy1), .px_valid(v[2]), .px_x(x_l),
        .px_y(y_l), .px_bimm(bi_l), .px_mt(mt_l), .px_ready(px_ready), .step(line_step), .done(sdone[2]));
    zm_blit_tri st3 (.clk(clk), .rst(rst), .go(go[3]), .color(f_color), .bg(f_bg), .mt(f_mt), .ht_on(ht_on),
        .ht_bit(ht_bit), .x0(sx(f_x0)), .y0(sx(f_y0)), .x1(sx(f_x1)), .y1(sx(f_y1)), .x2(sx(f_x2)), .y2(sx(f_y2)),
        .cx0(cx0), .cx1(cx1), .ey0(ey0), .ey1(ey1), .hx(hx_t), .hy(hy_t), .px_valid(v[3]), .px_x(x_t),
        .px_y(y_t), .px_bimm(bi_t), .px_mt(mt_t), .px_ready(px_ready), .done(sdone[3]));

    // One destination address generator for all four: D = dlin + y * stride + x, walked with
    // y from the op's first row (zm_blit_row), each sequencer's own: BLIT's (DESC: the box's
    // bottom), a LINE's y0 (walking up when y1 < y0), else the box's top.
    wire signed [17:0] px_y = is_blit ? y_b : is_fill ? y_f : is_line ? y_l : y_t;
    wire signed [17:0] px_x = is_blit ? x_b : is_fill ? x_f : is_line ? x_l : x_t;
    wire signed [17:0] d_ys = is_blit && f_con[6] ? ey1 - 18'sd1 : is_line ? sx(f_y0) : ey0;
    wire d_dn = is_blit ? f_con[6] : is_line && !(sx(f_y0) < sx(f_y1));
    wire [22:0] d_addr;
    zm_blit_row rd (.clk(clk), .base(dlin), .stride(f_d_stride), .xorg(18'sd0), .yorg(18'sd0), .ys(d_ys),
        .dn(d_dn), .ld(|go), .y(px_y), .x(px_x), .addr(d_addr));
    wire [7:0] px_mt = is_blit ? f_mt : is_fill ? mt_f : is_line ? mt_l : mt_t;
    wire [7:0] px_bimm = is_fill ? bi_f : is_line ? bi_l : is_blit ? 8'd0 : bi_t;
    // {KEY_EN, USEC, USEB, USEA}: BLIT's own, FILL/LINE/TRIANGLE read the destination only
    wire [3:0] px_flags = is_blit ? {f_con[3], f_con[2], f_con[1], f_con[0]} : 4'b0100;
    wire px_idle, wrote;
    zm_blit_px pxu (.clk(clk), .rst(rst), .px_valid(|v), .px_ready(px_ready), .px_dst(d_addr),
        .px_aaddr(aaddr), .px_baddr(baddr), .px_bimm(px_bimm), .px_mt(px_mt), .px_key(f_key), .px_flags(px_flags),
        .ordered(is_blit && overlap), .px_idle(px_idle), .wrote(wrote), .rd_req_valid(rd_req_valid), .rd_req_ready(rd_req_ready),
        .rd_req_addr(rd_req_addr), .rd_rsp_valid(rd_rsp_valid), .rd_rsp_data(rd_rsp_data),
        .wr_req_valid(wr_req_valid), .wr_req_ready(wr_req_ready), .wr_req_addr(wr_req_addr),
        .wr_req_data(wr_req_data), .wr_req_strb(wr_req_strb));

    // {op[2:0], core st, pixel unit idle, rd valid/ready, wr valid/ready, wr_pending, sequencer px_valid}
    assign dbg = {op[2:0], st, px_idle, rd_req_valid, rd_req_ready, wr_req_valid, wr_req_ready, wr_pending, v};
    wire counts = op == ZM_BLIT_CMD_BLIT || op == ZM_BLIT_CMD_TRIANGLE;
    wire [31:0] fill_cost = f_w * f_h;
    always @(posedge clk) begin
        go <= 4'd0;
        if (rst) st <= IDLE;
        else case (st)
            IDLE: if (start) begin op <= f_cmd; cost <= 32'd0; st <= CHK; end
            CHK: if (chk_done) begin
                if (chk_ok && op >= 1 && op <= 4) begin
                    go <= 4'd1 << (op - 8'd1);
                    if (is_fill) cost <= fill_cost;
                    st <= RUN;
                end else begin cost <= 32'd0; st <= FIN; end
            end
            RUN: begin
                if (counts ? wrote : line_step && is_line) cost <= cost + 32'd1;
                if (|sdone) st <= DRAIN;
            end
            DRAIN: begin
                if (counts && wrote) cost <= cost + 32'd1;
                if (px_idle && !wr_pending) st <= FIN;
            end
            default: st <= IDLE;
        endcase
    end
endmodule
