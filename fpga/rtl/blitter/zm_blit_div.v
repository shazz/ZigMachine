// Unsigned restoring divider for TRIANGLE's edge setup, one quotient bit per clock (17 clocks).
// The caller guarantees a 17-bit quotient, num < den * 2^17 (so the remainder starts as num's
// top 16 bits and only the low 17 are walked), and holds num and den from `go` until `done`:
// the bits are read from num in place (num[cnt]), no shift register. zm_blit_tri's numerators
// are dx * t + dy * 2^16 with |dx| * t < dy * 2^16, i.e. in [0, dy * 2^17). `done` is a one-clock
// pulse; q and r hold until the next go.
`default_nettype none

module zm_blit_div (
    input  wire        clk,
    input  wire        rst,
    input  wire        go,
    input  wire [32:0] num,
    input  wire [15:0] den,        // non-zero, above num[32:17]
    output reg         done,
    output reg [16:0]  q,
    output reg [15:0]  r
);
    reg        run;
    reg [4:0]  cnt;                 // the numerator bit walked now: 16 down to 0
    wire [16:0] sh = {r, num[cnt]};
    wire [17:0] sub = {1'b0, sh} - {2'b00, den};
    wire        ge = !sub[17];

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) run <= 1'b0;
        else if (go) begin
            run <= 1'b1; cnt <= 5'd16; r <= num[32:17];
        end else if (run) begin
            r <= ge ? sub[15:0] : sh[15:0];
            q <= {q[15:0], ge};      // 17 shifts: every bit of the last quotient is gone
            cnt <= cnt - 5'd1;
            if (cnt == 5'd0) begin run <= 1'b0; done <= 1'b1; end
        end
    end
endmodule
