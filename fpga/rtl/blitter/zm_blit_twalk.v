// One TRIANGLE edge, walked a scanline at a time: x = ax + floor(dx * t / dy) at line t,
// exactly the per-line divide of machine/blitter_ops.zig crossSpan, with no divide per line.
// The step is (qd, rd) = floor-divmod(dx, dy), 0 <= rd < dy, and the walker keeps the
// remainder r (0 <= r < dy) of dx * t / dy: a line adds qd to x and rd to r (sa), then, if
// r reached dy, takes dy back and carries one into x (sb). One adder for r serves both steps
// (r + rd, r - dy) and the carry is the sign of r - dy: no compare chain.
// Loading (zm_blit_tri): clr zeroes x and r; ld loads (qd, rd, dy). The start (x at the first
// visible line, and its remainder) goes in as a step: ld (ax + q0, r0), sa from x = r = 0.
`default_nettype none

module zm_blit_twalk (
    input  wire               clk,
    input  wire               clr,
    input  wire               ld,
    input  wire [15:0]        kq,      // qd, or ax + q0 for the start step
    input  wire [15:0]        kr,      // rd, or r0
    input  wire [15:0]        kdy,
    input  wire               sa,
    input  wire               sb,
    output reg  signed [15:0] x
);
    reg [15:0] qd, rd, dy;
    reg [16:0] r;
    wire [17:0] radd = {1'b0, r} + (sa ? {2'b00, rd} : -{2'b00, dy});
    wire carry = sb && !radd[17];
    always @(posedge clk) begin
        if (ld) begin qd <= kq; rd <= kr; dy <= kdy; end
        if (clr) begin
            x <= 16'sd0; r <= 17'd0;
        end else begin
            if (sa || carry) x <= x + (sa ? qd : 16'd0) + {15'd0, carry};
            if (sa || carry) r <= radd[16:0];
        end
    end
endmodule
