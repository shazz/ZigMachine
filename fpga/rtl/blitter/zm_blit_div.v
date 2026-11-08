// Unsigned restoring divider for TRIANGLE's edge setup, one quotient bit per clock (16 clocks).
// The caller guarantees a 16-bit quotient: num < den * 2^16, i.e. num[31:16] < den, which holds
// for both of an edge's divides (|dx| / dy, and |dx| * t0 / dy with t0 < dy), so the remainder
// starts as num's high half and only the low half is shifted through. `done` is a one-clock
// pulse; q and r hold until the next go. `clr` zeroes them in one clock (an edge whose first
// line is its top: the start offset is 0 / dy, nothing to divide).
`default_nettype none

module zm_blit_div (
    input  wire        clk,
    input  wire        rst,
    input  wire        go,
    input  wire        clr,
    input  wire [31:0] num,
    input  wire [15:0] den,        // non-zero, above num[31:16]
    output reg         done,
    output reg [15:0]  q,
    output reg [15:0]  r
);
    reg        run;
    reg [4:0]  cnt;
    reg [15:0] n;
    reg [15:0] d;
    wire [16:0] sh = {r, n[15]};
    wire [17:0] sub = {1'b0, sh} - {2'b00, d};
    wire        ge = !sub[17];

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) run <= 1'b0;
        else if (clr) begin
            q <= 16'd0; r <= 16'd0;
        end else if (go) begin
            run <= 1'b1; cnt <= 5'd16; n <= num[15:0]; d <= den; r <= num[31:16]; q <= 16'd0;
        end else if (run) begin
            r <= ge ? sub[15:0] : sh[15:0];
            q <= {q[14:0], ge};
            n <= {n[14:0], 1'b0};
            cnt <= cnt - 5'd1;
            if (cnt == 5'd1) begin run <= 1'b0; done <= 1'b1; end
        end
    end
endmodule
