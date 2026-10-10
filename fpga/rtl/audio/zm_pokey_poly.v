// POKEY's polynomial counters (zm_pokey.v): Fibonacci shift registers shifting
// right, the new bit XNORed in at the top, output = bit 0, clocked every machine
// cycle. XNOR makes all-zero a live state, so `clr` (init mode) holds them at 0.
// The 9-bit poly is the 17-bit register shortened: its feedback enters at bit 8
// (and bit 16), so bits 0..8 cycle alone. Trinomials x^4+x+1, x^5+x^2+1,
// x^9+x^4+1, x^17+x^5+1: periods 15, 31, 511, 131071. The same registers as
// machine/audio/pokey.zig `Poly`, which the testbench holds this to.
`default_nettype none

module zm_pokey_poly (
    input  wire clk,
    input  wire clr,
    input  wire cen,
    input  wire nine,          // AUDCTL bit 7
    output wire p4,
    output wire p5,
    output wire p17
);
    reg [3:0]  s4 = 4'd0;
    reg [4:0]  s5 = 5'd0;
    reg [16:0] s17 = 17'd0;
    wire n4 = ~(s4[0] ^ s4[1]);
    wire n5 = ~(s5[0] ^ s5[2]);
    wire n9 = ~(s17[0] ^ s17[4]);
    wire n17 = ~(s17[0] ^ s17[5]);
    assign {p4, p5, p17} = {s4[0], s5[0], s17[0]};

    always @(posedge clk) begin
        if (clr) begin
            {s4, s5, s17} <= 0;
        end else if (cen) begin
            s4 <= {n4, s4[3:1]};
            s5 <= {n5, s5[4:1]};
            s17 <= nine ? {n9, s17[16:10], n9, s17[8:1]} : {n17, s17[16:1]};
        end
    end
endmodule

`default_nettype wire
