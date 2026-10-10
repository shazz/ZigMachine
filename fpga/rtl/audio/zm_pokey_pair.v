// Two POKEY channel counters, 1+2 or 3+4 (zm_pokey.v), independent or joined
// into one 16-bit counter (AUDCTL bit 4 / 3). The rules, from the Altirra
// Hardware Reference Manual's period formulas (N+4 cycles for one channel at
// 1.79 MHz, N+7 for a joined pair; (N+1) ticks on the 64 / 15 kHz bases):
//   - a counter decrements on each tick; a tick at 0 is a BORROW;
//   - after a borrow it is frozen 3 machine cycles, then reloads from its AUDF;
//   - joined, the low channel rolls over to 0xFF at its borrow and its borrows
//     tick the high one; when the high one borrows both freeze 6 cycles, then
//     reload: low byte = AUDF lo, high byte = AUDF hi;
//   - STIMER reloads both now and drops any pending reload.
// `b_lo` / `b_hi` are this cycle's borrows, valid while `cen` is high.
// machine/audio/pokey.zig `count` / `pair` is the same, line for line.
`default_nettype none

module zm_pokey_pair (
    input  wire       clk,
    input  wire       rst,
    input  wire       cen,
    input  wire       stimer,
    input  wire       joined,
    input  wire       tick_lo,      // the low channel's clock this cycle
    input  wire       tick_hi,      // the high channel's, when not joined
    input  wire [7:0] f_lo,
    input  wire [7:0] f_hi,
    output wire       b_lo,
    output wire       b_hi
);
    localparam [2:0] SINGLE = 3'd3, JOINED = 3'd6;
    reg [7:0] c_lo = 8'd0, c_hi = 8'd0;
    reg [2:0] p_lo = 3'd0, p_hi = 3'd0;
    wire t_hi = joined ? b_lo : tick_hi;

    assign b_lo = p_lo == 3'd0 && tick_lo && c_lo == 8'd0;
    assign b_hi = p_hi == 3'd0 && t_hi && c_hi == 8'd0;

    always @(posedge clk) begin
        if (rst) begin
            {c_lo, c_hi, p_lo, p_hi} <= 0;
        end else if (stimer) begin
            {c_lo, c_hi, p_lo, p_hi} <= {f_lo, f_hi, 6'd0};
        end else if (cen) begin
            if (p_lo != 3'd0) begin
                p_lo <= p_lo - 3'd1;
                if (p_lo == 3'd1) c_lo <= f_lo;
            end else if (tick_lo) begin
                if (c_lo != 8'd0) c_lo <= c_lo - 8'd1;
                else if (joined) c_lo <= 8'hFF;
                else p_lo <= SINGLE;
            end
            if (p_hi != 3'd0) begin
                p_hi <= p_hi - 3'd1;
                if (p_hi == 3'd1) c_hi <= f_hi;
            end else if (t_hi) begin
                if (c_hi != 8'd0) c_hi <= c_hi - 8'd1;
                else p_hi <= joined ? JOINED : SINGLE;
            end
            if (joined && b_hi) p_lo <= JOINED;
        end
    end
endmodule

`default_nettype wire
