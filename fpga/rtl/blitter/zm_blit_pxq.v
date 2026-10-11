// The back half of the pixel unit (zm_blit_px): the pixels whose reads are issued, in
// order, until each is written.
//   queue (2^LQ slots, LUTRAM) -> H (the head, its bytes in registers) -> the write buffer
// A slot is taken when zm_blit_px pushes a pixel (its reads all requested); the answered
// words land in it by tag (`rsp_*`), in any slot; a channel zm_blit_px did not read again
// (`p_reuse`) takes its byte from the word that channel last fetched (hw_*, kept in pixel
// order as the head leaves); the head leaves for H once every channel it needs has
// come back, so pixels are combined and written strictly in sequencer order.
// H computes D = LF(A,B,C) per bit and the key, and hands the byte to the write buffer: one
// aligned word with byte strobes, so consecutive bytes of one word go out as ONE write.
// The buffer is written out when the next byte belongs to another word, or when nothing
// is waiting that could join it (no head, or a head in another word): a byte never sits
// there while the unit idles or while an ordered op waits to read (zm_blit_px `ordered`).
// A keyed pixel is not written and not counted; a no-op pixel is counted and not written.
`default_nettype none

module zm_blit_pxq #(parameter LQ = 5) (
    input  wire          clk,
    input  wire          rst,
    // push: one pixel whose reads are all issued
    input  wire          push,
    input  wire [22:0]   p_dst,
    input  wire [7:0]    p_bimm,
    input  wire [2:0]    p_need,
    input  wire [2:0]    p_reuse,         // channels whose byte is in the word last fetched for them
    input  wire [1:0]    p_alane, p_blane,
    input  wire          p_nop,
    output wire [LQ-1:0] wslot,           // the slot the next push takes (zm_blit_px tags its reads with it)
    output wire          q_full,
    // an answer: the word of channel ch (0 A, 1 B, 2 C) of the pixel in `slot`
    input  wire          rsp_we,
    input  wire [LQ-1:0] rsp_slot,
    input  wire [1:0]    rsp_ch,
    input  wire [31:0]   rsp_word,
    // per op (constant while an op runs)
    input  wire [7:0]    mt, key,
    input  wire          ben, keyen,
    output wire          drained,         // no pixel in the queue, in H or in the write buffer
    output wire          wrote,
    output wire          wr_req_valid,
    input  wire          wr_req_ready,
    output wire [31:0]   wr_req_addr,
    output wire [31:0]   wr_req_data,
    output wire [3:0]    wr_req_strb
);
    localparam N = 1 << LQ;
    reg [LQ:0] wp, hp;                    // a wrap bit: equal = empty, differ by N = full
    assign wslot = wp[LQ-1:0];
    wire q_empty = wp == hp;
    assign q_full = wp == {~hp[LQ], hp[LQ-1:0]};
    wire [LQ-1:0] hs = hp[LQ-1:0];

    reg [22:0] q_dst [0:N-1];
    reg [7:0]  q_bimm [0:N-1];
    reg [31:0] q_a [0:N-1], q_b [0:N-1], q_c [0:N-1];
    reg [2:0]  q_need [0:N-1], q_reuse [0:N-1];
    reg [3:0]  q_lanes [0:N-1];
    reg        q_nop [0:N-1];
    reg [N-1:0] got_a, got_b, got_c;     // answers in: set by tag, cleared as the slot leaves

    always @(posedge clk) begin
        if (push) begin
            q_dst[wslot] <= p_dst; q_bimm[wslot] <= p_bimm; q_need[wslot] <= p_need; q_nop[wslot] <= p_nop;
            q_reuse[wslot] <= p_reuse; q_lanes[wslot] <= {p_blane, p_alane};
        end
        if (rsp_we && rsp_ch == 2'd0) q_a[rsp_slot] <= rsp_word;
        if (rsp_we && rsp_ch == 2'd1) q_b[rsp_slot] <= rsp_word;
        if (rsp_we && rsp_ch == 2'd2) q_c[rsp_slot] <= rsp_word;
    end

    // H: the head pixel, all its bytes in
    reg        hv, h_nop;
    reg [22:0] h_dst;
    reg [7:0]  h_a, h_b, h_c, h_bimm;
    wire [7:0] bval = ben ? h_b : h_bimm;
    wire skip = keyen && bval == key;
    wire [7:0] res;
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : lf
            assign res[i] = mt[{h_a[i], bval[i], h_c[i]}];
        end
    endgenerate

    // the write buffer: one aligned word, its strobes
    reg        cv;
    reg [20:0] c_word;
    reg [31:0] c_data;
    reg [3:0]  c_strb;
    wire h_wr = hv && !skip && !h_nop;
    wire same = cv && c_word == h_dst[22:2];
    // keep the buffer while the next byte may join it: H's, or the waiting head's
    wire keep = hv ? !(h_wr && !same) : !q_empty && q_dst[hs][22:2] == c_word;
    assign wr_req_valid = cv && !keep;
    assign wr_req_addr = {9'd0, c_word, 2'b00};
    assign wr_req_data = c_data;
    assign wr_req_strb = c_strb;
    wire wtake = wr_req_valid && wr_req_ready;
    wire h_ret = hv && (skip || h_nop || !cv || same || wtake);
    assign wrote = h_ret && !skip;

    wire [2:0] h_got = {got_c[hs], got_b[hs], got_a[hs]};
    wire h_load = !q_empty && h_got == q_need[hs] && (!hv || h_ret);
    assign drained = q_empty && !hv && !cv;
    wire [N-1:0] sbit = {{(N-1){1'b0}}, 1'b1} << rsp_slot, hbit = {{(N-1){1'b0}}, 1'b1} << hs;
    wire [N-1:0] wbit = {{(N-1){1'b0}}, 1'b1} << wslot;
    // the word each channel last fetched, in pixel order: a reusing pixel's byte comes from it
    reg [31:0] hw_a, hw_b, hw_c;
    wire [2:0] h_need = q_need[hs], h_reuse = q_reuse[hs];
    wire [3:0] h_lanes = q_lanes[hs];
    wire [31:0] wa = h_reuse[0] ? hw_a : q_a[hs], wb = h_reuse[1] ? hw_b : q_b[hs];
    wire [31:0] wc = h_reuse[2] ? hw_c : q_c[hs];
    wire [22:0] hd = q_dst[hs];

    always @(posedge clk) begin
        if (rst) begin
            wp <= 0; hp <= 0; hv <= 1'b0; cv <= 1'b0;
            got_a <= 0; got_b <= 0; got_c <= 0;
        end else begin
            if (push) wp <= wp + 1'b1;
            // an answer never lands in the slot leaving this clock: it leaves once all are in
            // a reused channel is in at the push; a fetched one when its answer lands
            got_a <= (got_a | (rsp_we && rsp_ch == 2'd0 ? sbit : 0) | (push && p_reuse[0] ? wbit : 0)) & ~(h_load ? hbit : 0);
            got_b <= (got_b | (rsp_we && rsp_ch == 2'd1 ? sbit : 0) | (push && p_reuse[1] ? wbit : 0)) & ~(h_load ? hbit : 0);
            got_c <= (got_c | (rsp_we && rsp_ch == 2'd2 ? sbit : 0) | (push && p_reuse[2] ? wbit : 0)) & ~(h_load ? hbit : 0);
            if (h_load) begin
                hp <= hp + 1'b1;
                hv <= 1'b1; h_dst <= q_dst[hs]; h_bimm <= q_bimm[hs]; h_nop <= q_nop[hs];
                // a channel not read is 0, as the machine has it (the slot keeps an older pixel's word)
                h_a <= h_need[0] ? wa >> {h_lanes[1:0], 3'b000} : 8'd0;
                h_b <= h_need[1] ? wb >> {h_lanes[3:2], 3'b000} : 8'd0;
                h_c <= h_need[2] ? wc >> {hd[1:0], 3'b000} : 8'd0;
                if (h_need[0]) hw_a <= wa;
                if (h_need[1]) hw_b <= wb;
                if (h_need[2]) hw_c <= wc;
            end else if (h_ret) hv <= 1'b0;
            if (h_ret && h_wr) begin
                cv <= 1'b1;
                c_word <= h_dst[22:2];
                if (same) begin
                    c_data[{h_dst[1:0], 3'b000} +: 8] <= res;
                    c_strb <= c_strb | (4'b0001 << h_dst[1:0]);
                end else begin
                    c_data <= {4{res}};
                    c_strb <= 4'b0001 << h_dst[1:0];
                end
            end else if (wtake) cv <= 1'b0;
        end
    end
endmodule
