// One TRIANGLE edge, walked a scanline at a time: x = ax + floor(dx * t / dy) at line t, exactly
// the per-line divide of machine/blitter_ops.zig crossSpan, with no divide at all (a Bresenham
// walk on the floor itself, for either sign of dx). e = dx * t mod dy (the floor remainder,
// 0 <= e < dy between lines) starts at 0 with x = ax; a line adds dx to e (sa), then, once a
// clock, sb brings e back into [0, dy):
//   dx >= 0: while e >= dy: e -= dy, x += 1      dx < 0: while e < 0: e += dy, x -= 1
// `carry` is high on each such step. One adder does all three (e + dx, e - dy, e + dy), its
// operand picked by sa and the sign alone, so each bit is one LUT on the carry chain; x's adder
// likewise (+ax once, then +1 or -1).
// Loading: clr zeroes x and e, ini adds ax to x and takes dx, dy and the sign.
`default_nettype none

module zm_blit_twalk (
    input  wire               clk,
    input  wire               clr,
    input  wire               ini,
    input  wire [15:0]        kax,     // the edge's top x
    input  wire signed [16:0] kdx,
    input  wire [15:0]        kdy,
    input  wire               sa,
    input  wire               sb,
    output wire               carry,   // sb moved x this clock
    output reg  signed [15:0] x
);
    reg signed [16:0] dx;
    reg [15:0] dy;
    reg signed [17:0] e;            // in (-2^16, 2^16): after sa, [-|dx|, 2 dy)
    wire neg = dx[16];
    // sa: + dx; sb: + dy (dx < 0) or - dy as ~dy + 1 (dx >= 0)
    wire [17:0] op = sa ? {dx[16], dx} : neg ? {2'b00, dy} : ~{2'b00, dy};
    wire signed [17:0] eadd = e + op + {17'd0, !sa && !neg};
    assign carry = sb && !sa && (neg ? e[17] : !eadd[17]);
    always @(posedge clk) begin
        if (ini) begin dx <= kdx; dy <= kdy; end
        if (clr) begin
            x <= 16'sd0; e <= 18'sd0;
        end else begin
            if (ini || carry) x <= x + (ini ? kax : neg ? 16'hFFFF : 16'h0001);
            if (sa || carry) e <= eadd;
        end
    end
endmodule
