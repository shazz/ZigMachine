// The blitter engine: decodes the register block, runs the checks (zm_blit_chk), starts the
// sequencer of the op (FILL, BLIT, LINE, TRIANGLE, AFFINE/MAP: each turns geometry into pixels) and
// feeds their pixels through the one pixel unit (zm_blit_px), which owns the memory ports
// and keeps many pixels in flight; DRAIN waits until the last is written and landed.
// CYCLES is the Zig machine's model: pixels written (BLIT, TRIANGLE, AFFINE, MAP), every step (LINE),
// W*H (FILL, clipped pixels included); 0 when the checks refuse the op.
//   IDLE -> CHK -> RUN (sequencer) -> DRAIN (pixel unit idle, writes landed) -> FIN -> IDLE
`default_nettype none
`include "memmap.vh"

module zm_blit_core (
    input  wire         clk,
    input  wire         rst,
    input  wire         start,
    input  wire [511:0] rf,
    output wire [3:0]   ht_y,            // the halftone row of the pixel (zm_blit_regs LUTRAM)
    input  wire [15:0]  ht_row,
    input  wire         ht_nz,
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
    reg [5:0] go;           // {MAP, AFFINE, TRIANGLE, LINE, FILL, BLIT}: a one-clock start
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
    wire ht_on = f_con2[2] || ht_nz;
    wire fill_mt = f_con2[1] && f_mt != 8'hCC;   // ZM_MT_B combined is the plain write
    // Registered decodes and clip box: both are functions of registers that cannot change while
    // BUSY (writes are dropped), so a copy one clock behind is exact by the time CHK reads it: the
    // COMMAND store that starts an op comes at least a clock after the stores that set them up.
    // Without the copies the pixel unit's inputs were 11 to 15 logic levels from the register
    // block, -1.5 ns at 100 MHz on the board (Vivado, 2026-10-10).
    reg is_blit, is_fill, is_line, is_tri, is_aff, is_tex;
    always @(posedge clk) begin
        is_blit <= op == ZM_BLIT_CMD_BLIT; is_fill <= op == ZM_BLIT_CMD_FILL; is_line <= op == ZM_BLIT_CMD_LINE;
        is_tri <= op == ZM_BLIT_CMD_TRIANGLE;
        is_aff <= op == ZM_BLIT_CMD_AFFINE; is_tex <= op == ZM_BLIT_CMD_AFFINE || op == ZM_BLIT_CMD_MAP;
    end

    wire signed [17:0] ccx0, ccy0, ccx1, ccy1, ex0, ey0, ex1, ey1;
    reg signed [17:0] cx0, cy0, cx1, cy1;
    zm_blit_clip clip (.con(f_con), .ds(f_d_stride), .clip_x(f_clip_x), .clip_y(f_clip_y),
        .clip_w(f_clip_w), .clip_h(f_clip_h), .x0(ccx0), .y0(ccy0), .x1(ccx1), .y1(ccy1));
    always @(posedge clk) {cx0, cy0, cx1, cy1} <= {ccx0, ccy0, ccx1, ccy1};
    wire chk_done, chk_ok, overlap;
    zm_blit_chk chk (.clk(clk), .go(start), .cmd(f_cmd), .use_a(f_con[0]), .use_b(f_con[1]), .abs_src(abs_src), .desc(f_con[6]),
        .d_base(f_d_base), .a_base(f_a_base), .b_base(f_b_base), .ds(f_d_stride), .a_stride(f_a_stride),
        .b_stride(f_b_stride), .w(f_w), .h(f_h), .umask(f_umask), .vmask(f_vmask), .nspan(f_span_count),
        .span_base(f_span_base), .x0(sx(f_x0)), .y0(sx(f_y0)), .x1(sx(f_x1)), .y1(sx(f_y1)),
        .x2(sx(f_x2)), .y2(sx(f_y2)), .cx0(cx0), .cy0(cy0), .cx1(cx1), .cy1(cy1),
        .done(chk_done), .ok(chk_ok), .ex0(ex0), .ey0(ey0), .ex1(ex1), .ey1(ey1), .overlap(overlap));

    // The sequencers: each turns its op's geometry into pixels (x, y). FILL is the BLIT box walk
    // with no source and no DESC (the walks were identical: one sequencer, SOC_REVIEW F5); the
    // colour (COLOR, or the halftone's pick at the pixel), the minterm and the channels are
    // decided here once for all of them.
    wire v_r, v_l, v_t, d_r, d_l, d_t;     // px_valid / done: the box walk (BLIT, FILL), LINE, TRIANGLE
    wire signed [17:0] x_r, y_r, x_l, y_l, x_t, y_t;
    wire [22:0] aaddr, baddr;
    wire px_ready, line_step;
    zm_blit_blit sb (.clk(clk), .rst(rst), .go(go[0] | go[1]), .a_lin(a_lin), .b_lin(b_lin), .a_stride(f_a_stride),
        .b_stride(f_b_stride), .desc(f_con[6] && is_blit), .x0(sx(f_x0)), .y0(sx(f_y0)), .ex0(ex0), .ey0(ey0),
        .ex1(ex1), .ey1(ey1), .px_valid(v_r), .px_x(x_r), .px_y(y_r), .px_aaddr(aaddr), .px_baddr(baddr),
        .px_ready(px_ready), .done(d_r));
    zm_blit_line sl (.clk(clk), .rst(rst), .go(go[2]), .x0(sx(f_x0)), .y0(sx(f_y0)),
        .x1(sx(f_x1)), .y1(sx(f_y1)), .cx0(cx0), .cy0(cy0), .cx1(cx1), .cy1(cy1), .px_valid(v_l), .px_x(x_l),
        .px_y(y_l), .px_ready(px_ready), .step(line_step), .done(d_l));
    zm_blit_tri st3 (.clk(clk), .rst(rst), .go(go[3]), .x0(sx(f_x0)), .y0(sx(f_y0)), .x1(sx(f_x1)), .y1(sx(f_y1)),
        .x2(sx(f_x2)), .y2(sx(f_y2)), .cx0(cx0), .cx1(cx1), .ey0(ey0), .ey1(ey1), .px_valid(v_t), .px_x(x_t),
        .px_y(y_t), .px_ready(px_ready), .done(d_t));
    // AFFINE and MAP: their own destination address, the texel's as channel B, their list or map
    // through the aux side of the read port (zm_blit_rdmux)
    wire v_x, d_x, aux_valid, aux_ready, aux_rsp, px_rd_valid, px_rd_ready, px_rsp;
    wire [22:0] aux_addr, t_dst, t_baddr;
    wire [31:0] px_rd_addr;
    zm_blit_tex sx_ (.clk(clk), .rst(rst), .go_aff(go[4]), .go_map(go[5]), .a_lin(a_lin), .a_stride(f_a_stride),
        .umask(f_umask), .vmask(f_vmask), .uoff(f_x1), .voff(f_y1), .tclip(f_con2[6]),
        .list(is_aff ? f_span_base[22:0] : f_b_base[22:0]), .nspan(f_span_count), .ms(f_b_stride),
        .x0(sx(f_x0)), .y0(sx(f_y0)), .ex0(ex0), .ey0(ey0), .ex1(ex1), .ey1(ey1), .cx0(cx0), .cy0(cy0),
        .cx1(cx1), .cy1(cy1), .dlin(dlin), .ds(f_d_stride), .aux_valid(aux_valid), .aux_ready(aux_ready),
        .aux_addr(aux_addr), .aux_rsp_valid(aux_rsp), .aux_rsp_data(rd_rsp_data), .px_valid(v_x),
        .px_ready(px_ready), .px_dst(t_dst), .px_baddr(t_baddr), .done(d_x));
    zm_blit_rdmux rmx (.clk(clk), .rst(rst), .px_valid(px_rd_valid), .px_ready(px_rd_ready), .px_addr(px_rd_addr),
        .px_rsp(px_rsp), .aux_valid(aux_valid), .aux_ready(aux_ready), .aux_addr(aux_addr), .aux_rsp(aux_rsp),
        .rd_req_valid(rd_req_valid), .rd_req_ready(rd_req_ready), .rd_req_addr(rd_req_addr),
        .rd_rsp_valid(rd_rsp_valid));
    wire [3:0] v = {v_t | v_x, v_l, v_r && is_fill, v_r && is_blit};   // for dbg: TRIANGLE's bit also AFFINE/MAP

    // One destination address generator for all: D = dlin + y * stride + x, walked with
    // y from the op's first row (zm_blit_row), each sequencer's own: BLIT's (DESC: the box's
    // bottom), a LINE's y0 (walking up when y1 < y0), else the box's top.
    wire signed [17:0] px_y = is_line ? y_l : is_tri ? y_t : y_r;
    wire signed [17:0] px_x = is_line ? x_l : is_tri ? x_t : x_r;
    wire signed [17:0] d_ys = is_blit && f_con[6] ? ey1 - 18'sd1 : is_line ? sx(f_y0) : ey0;
    wire d_dn = is_blit ? f_con[6] : is_line && !(sx(f_y0) < sx(f_y1));
    wire [22:0] d_addr;
    zm_blit_row rd (.clk(clk), .base(dlin), .stride(f_d_stride), .xorg(18'sd0), .yorg(18'sd0), .ys(d_ys),
        .dn(d_dn), .ld(|go), .y(px_y), .x(px_x), .addr(d_addr));
    // B as a constant: COLOR, or (FILL, TRIANGLE) the halftone's pick at the pixel; 0 for a BLIT
    wire ht_bit;
    assign ht_y = px_y[3:0];
    zm_blit_htbit htb (.row(ht_row), .x(px_x[3:0]), .bit_o(ht_bit));
    wire pick_bg = ht_on && !is_line && !ht_bit;
    wire [7:0] px_bimm = is_blit || is_tex ? 8'd0 : pick_bg ? f_bg : f_color;
    // FILL ignores MINTERM unless CON2.FILL_MT (MT_B: a plain write that reads nothing)
    wire [7:0] px_mt = is_fill && !fill_mt ? 8'hCC : f_mt;
    // {KEY_EN, USEC, USEB, USEA}: BLIT's own, FILL/LINE/TRIANGLE read the destination only, AFFINE/MAP
    // the texel as B (keyed by KEY_EN) and the destination if the minterm wants it
    wire [3:0] px_flags = is_blit ? {f_con[3], f_con[2], f_con[1], f_con[0]} : is_tex ? {f_con[3], 3'b110} : 4'b0100;
    // A pixel the minterm cannot change touches no memory (zm_blit_px): C only, and LF(0, b, c) == c
    // for every bit b of the constant B, i.e. m[{0,0,c}] == c where b has a 0 and m[{0,1,c}] == c
    // where a 1. B is COLOR or BG_COLOR (a BLIT's: 0), all fixed during an op, so both answers are registered
    // and the pixel only picks one (the halftone read stays off this path: -0.45 ns at 125 MHz).
    function ident(input [7:0] m, input [7:0] b);
        ident = (&b || (!m[0] && m[1])) && (~|b || (!m[2] && m[3]));
    endfunction
    reg id_fg, id_bg, id_0;
    always @(posedge clk) begin
        id_fg <= ident(px_mt, f_color); id_bg <= ident(px_mt, f_bg); id_0 <= ident(px_mt, 8'd0);
    end
    // a BLIT's B constant is 0, and it is C only when it reads nothing else and keys nothing
    wire px_nop = is_tex ? 1'b0 : is_blit ? px_flags == 4'b0100 && id_0 : (pick_bg ? id_bg : id_fg);
    // AFFINE's spans may cover a pixel twice: when the minterm reads C, every read waits for the
    // writes before it and C words are not reused (a MAP box, like every other op, never does)
    wire c_dep = !(f_mt[0] == f_mt[1] && f_mt[2] == f_mt[3] && f_mt[4] == f_mt[5] && f_mt[6] == f_mt[7]);
    reg ord_c;
    always @(posedge clk) ord_c <= is_aff && c_dep;
    wire px_idle, wrote;
    zm_blit_px pxu (.clk(clk), .rst(rst), .px_valid(v_r | v_l | v_t | v_x), .px_ready(px_ready),
        .px_dst(is_tex ? t_dst : d_addr), .px_aaddr(aaddr), .px_baddr(is_tex ? t_baddr : baddr), .px_bimm(px_bimm), .px_nop(px_nop), .px_mt(px_mt), .px_key(f_key), .px_flags(px_flags),
        .ordered((is_blit || is_tex) && overlap || ord_c), .ordered_c(ord_c), .px_idle(px_idle), .wrote(wrote),
        .rd_req_valid(px_rd_valid), .rd_req_ready(px_rd_ready), .rd_req_addr(px_rd_addr), .rd_rsp_valid(px_rsp),
        .rd_rsp_data(rd_rsp_data),
        .wr_req_valid(wr_req_valid), .wr_req_ready(wr_req_ready), .wr_req_addr(wr_req_addr),
        .wr_req_data(wr_req_data), .wr_req_strb(wr_req_strb));

    // {op[2:0], core st, pixel unit idle, rd valid/ready, wr valid/ready, wr_pending, sequencer px_valid}
    assign dbg = {op[2:0], st, px_idle, rd_req_valid, rd_req_ready, wr_req_valid, wr_req_ready, wr_pending, v};
    wire counts = op == ZM_BLIT_CMD_BLIT || op == ZM_BLIT_CMD_TRIANGLE || op == ZM_BLIT_CMD_AFFINE || op == ZM_BLIT_CMD_MAP;
    wire [31:0] fill_cost = f_w * f_h;
    always @(posedge clk) begin
        go <= 6'd0;
        if (rst) st <= IDLE;
        else case (st)
            IDLE: if (start) begin op <= f_cmd; cost <= 32'd0; st <= CHK; end
            CHK: if (chk_done) begin
                if (chk_ok && (op >= 8'd1 && op <= 8'd4 || op == 8'd6 || op == 8'd7)) begin
                    go <= 6'd1 << (op >= 8'd6 ? op - 8'd2 : op - 8'd1);   // 5 is the QUEUE's
                    if (is_fill) cost <= fill_cost;
                    st <= RUN;
                end else begin cost <= 32'd0; st <= FIN; end
            end
            RUN: begin
                if (counts ? wrote : line_step && is_line) cost <= cost + 32'd1;
                if (d_r | d_l | d_t | d_x) st <= DRAIN;
            end
            DRAIN: begin
                if (counts && wrote) cost <= cost + 32'd1;
                if (px_idle && !wr_pending) st <= FIN;
            end
            default: st <= IDLE;
        endcase
    end
endmodule
