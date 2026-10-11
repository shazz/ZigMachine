// The pixel unit: reads the channels the minterm actually depends on (a minterm that
// ignores A, B or C never causes that read, which is invisible: reads have no side
// effects), computes D = LF(A,B,C) per bit, and writes the byte. A pixel whose B equals
// the key (KEY_EN) is not written and not counted.
//
// Pipelined: the issue stage (I, here) requests a pixel's reads and moves on to the next
// pixel without waiting for the data; up to 2^LQ pixels wait for theirs in zm_blit_pxq,
// which combines and writes them in order. Each read carries a tag (the pixel's slot and
// channel) through a FIFO, since the answers come back in request order with no
// back-pressure.
//
// Word reuse: a channel whose byte lies in the word that channel asked for last (P checks
// it against lw_*) is not read again; zm_blit_pxq takes the byte from that word, in pixel
// order. A row of W bytes costs W/4 reads per channel instead of W. Safe where the word
// cannot have changed since it was read in port order: C, because no other pixel of the
// op writes this pixel's byte (below); A/B only when the op is not `ordered` (no write of
// the op touches a source). Nothing is reused across ops (lw_v clears whenever the unit is
// idle, which DRAIN guarantees between ops).
//
// Memory ports (one word = 32 bits, the byte lane is addr[1:0]): responses in request
// order at least one clock later; a write may carry several strobes (bytes of one word).
// Port order is the contract: a read sees every write taken before it, and a read and a
// write taken in the same clock are the read first.
//
// Ordering. A read is issued ahead of the writes of the pixels before it, so it may only
// run ahead of a write it provably cannot alias:
//   - C (the destination byte) never aliases an earlier pixel's write: an op never visits
//     the same (x, y) twice and 0 <= x < D_STRIDE (the clip), so every pixel of an op
//     writes its own byte;
//   - A and B may: a BLIT over its own destination (a scroll, a smear). zm_blit_chk
//     proves the source rectangles and the destination span disjoint from the registers;
//     when it cannot (`ordered`), a read waits until every earlier pixel's write has been
//     taken by the port (queue, H and the write buffer empty), which is the v1 order.
//
// A pixel the minterm cannot change touches no memory: channel C only (no A, no B, no key)
// and LF(0, b, c) == c for every bit b of the constant B, e.g. a halftone's background
// bit OR'd (the glenz's rows of the other object) or XOR'd into the destination. Reading
// the byte and writing it back unchanged leaves memory as it was, so the pixel is counted
// (CYCLES is pixels written) and passed with no access.
`default_nettype none

module zm_blit_px #(parameter LQ = 5, parameter LT = 5) (
    input  wire              clk,
    input  wire              rst,
    input  wire              px_valid,
    output wire              px_ready,
    input  wire [22:0]       px_dst,          // linear byte address of the destination pixel (= channel C)
    input  wire [22:0]       px_aaddr, px_baddr,
    input  wire [7:0]        px_bimm,         // B when channel B is not read (a constant colour, or 0)
    input  wire [7:0]        px_mt, px_key,   // per op: the same for every pixel of one op
    input  wire [3:0]        px_flags,        // {KEY_EN, USEC, USEB, USEA}, per op
    input  wire              ordered,         // per op: A/B reads wait for the earlier writes
    output wire              px_idle,
    output wire              wrote,           // a pixel was written (or passed as a no-op) this clock
    output wire              rd_req_valid,
    input  wire              rd_req_ready,
    output wire [31:0]       rd_req_addr,
    input  wire              rd_rsp_valid,
    input  wire [31:0]       rd_rsp_data,
    output wire              wr_req_valid,
    input  wire              wr_req_ready,
    output wire [31:0]       wr_req_addr,
    output wire [31:0]       wr_req_data,
    output wire [3:0]        wr_req_strb
);
    function [2:0] need(input [7:0] m, input aen, ben, cen, ken);
        reg a_dc, b_dc, c_dc;
        begin
            a_dc = m[3:0] == m[7:4];
            b_dc = m[1:0] == m[3:2] && m[5:4] == m[7:6];
            c_dc = m[0] == m[1] && m[2] == m[3] && m[4] == m[5] && m[6] == m[7];
            need = {cen && !c_dc, ben && (ken || !b_dc), aen && !a_dc};
        end
    endfunction

    // LF(0, b, c) == c for each bit b of `b`: m[{0,0,c}] == c where b has a 0, m[{0,1,c}] == c where a 1
    function ident(input [7:0] m, input [7:0] b);
        ident = (&b || (!m[0] && m[1])) && (~|b || (!m[2] && m[3]));
    endfunction

    // per op
    reg [7:0] mt, key;
    reg ben, keyen;

    // P: the pixel just taken from the sequencer, its reuse decided against the words already asked for
    reg        pv, p_nop;
    reg [22:0] p_dst, p_a, p_b;
    reg [7:0]  p_bimm;
    reg [2:0]  p_need;
    // the word each channel last asked for (addr[22:2]), valid until the unit next idles
    reg [20:0] lw_a, lw_b, lw_c;
    reg [2:0]  lw_v;
    wire [2:0] may_reuse = {1'b1, !ordered, !ordered};   // C always; A/B unless sources may be written
    wire [2:0] hit = p_need & may_reuse & lw_v
        & {lw_c == p_dst[22:2], lw_b == p_b[22:2], lw_a == p_a[22:2]};
    wire [2:0] fetch = p_need & ~hit;

    // I: the pixel whose reads are being requested
    reg        iv, i_nop;
    reg [22:0] i_dst, i_a, i_b;
    reg [7:0]  i_bimm;
    reg [2:0]  i_need, i_pend, i_reuse;   // channels used / still to request / taken from the last word: {C,B,A}

    wire [LQ-1:0] wslot;
    wire q_full, drained;
    reg [LT:0] tw, tr;           // the tag FIFO: a wrap bit, as the queue's pointers
    wire t_full = tw == {~tr[LT], tr[LT-1:0]};
    // ordered: no read while an earlier pixel's write is not yet taken by the port
    wire may_read = !ordered || drained;

    wire [2:0] low = i_pend & (~i_pend + 3'd1);
    wire [1:0] ch = low[0] ? 2'd0 : low[1] ? 2'd1 : 2'd2;
    wire [22:0] raddr = low[0] ? i_a : low[1] ? i_b : i_dst;
    assign rd_req_valid = iv && i_pend != 3'd0 && !q_full && !t_full && may_read;
    assign rd_req_addr = {9'd0, raddr};
    wire rtake = rd_req_valid && rd_req_ready;
    wire [2:0] pend_after = i_pend & ~(rtake ? low : 3'd0);
    wire push = iv && !q_full && pend_after == 3'd0;
    wire p_move = pv && (!iv || push);
    assign px_ready = !pv || p_move;
    wire acc = px_valid && px_ready;
    wire [2:0] nd = need(px_mt, px_flags[0], px_flags[1], px_flags[2], px_flags[3]);
    wire px_nop = px_flags == 4'b0100 && ident(px_mt, px_bimm);

    // the tags: {slot, channel} of every read in flight, in request order
    reg [LQ+1:0] tag [0:(1 << LT)-1];
    wire [LQ+1:0] t_head = tag[tr[LT-1:0]];
    always @(posedge clk) if (rtake) tag[tw[LT-1:0]] <= {wslot, ch};

    zm_blit_pxq #(.LQ(LQ)) q (.clk(clk), .rst(rst), .push(push), .p_dst(i_dst), .p_bimm(i_bimm),
        .p_need(i_need), .p_reuse(i_reuse), .p_alane(i_a[1:0]), .p_blane(i_b[1:0]), .p_nop(i_nop),
        .wslot(wslot), .q_full(q_full), .rsp_we(rd_rsp_valid), .rsp_slot(t_head[LQ+1:2]), .rsp_ch(t_head[1:0]),
        .rsp_word(rd_rsp_data), .mt(mt), .key(key), .ben(ben), .keyen(keyen),
        .drained(drained), .wrote(wrote), .wr_req_valid(wr_req_valid), .wr_req_ready(wr_req_ready),
        .wr_req_addr(wr_req_addr), .wr_req_data(wr_req_data), .wr_req_strb(wr_req_strb));

    assign px_idle = !pv && !iv && drained;

    always @(posedge clk) begin
        if (rst) begin
            pv <= 1'b0; iv <= 1'b0; tw <= 0; tr <= 0; lw_v <= 3'd0;
        end else begin
            if (rtake) tw <= tw + 1'b1;
            if (rd_rsp_valid) tr <= tr + 1'b1;
            if (acc) begin
                pv <= 1'b1;
                p_dst <= px_dst; p_a <= px_aaddr; p_b <= px_baddr; p_bimm <= px_bimm;
                p_nop <= px_nop; p_need <= px_nop ? 3'd0 : nd;
                mt <= px_mt; key <= px_key; ben <= px_flags[1]; keyen <= px_flags[3];
            end else if (p_move) pv <= 1'b0;
            if (p_move) begin
                iv <= 1'b1;
                i_dst <= p_dst; i_a <= p_a; i_b <= p_b; i_bimm <= p_bimm; i_nop <= p_nop;
                i_need <= p_need; i_pend <= fetch; i_reuse <= hit;
                if (fetch[0]) lw_a <= p_a[22:2];
                if (fetch[1]) lw_b <= p_b[22:2];
                if (fetch[2]) lw_c <= p_dst[22:2];
                lw_v <= lw_v | fetch;
            end else begin
                if (push) iv <= 1'b0;
                i_pend <= pend_after;
                // between ops (and whenever the unit runs dry) nothing fetched is reused: the
                // op that just ended may have written those words
                if (px_idle) lw_v <= 3'd0;
            end
        end
    end
endmodule
