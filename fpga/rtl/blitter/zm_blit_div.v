// Unsigned restoring divider, one quotient bit per clock (32 clocks). `done` is a
// one-clock pulse; q and r hold until the next go. Used by TRIANGLE's edge walk.
`default_nettype none

module zm_blit_div (
    input  wire        clk,
    input  wire        rst,
    input  wire        go,
    input  wire [31:0] num,
    input  wire [16:0] den,        // non-zero
    output reg         done,
    output reg [31:0]  q,
    output reg [16:0]  r
);
    reg        run;
    reg [5:0]  cnt;
    reg [31:0] n;
    reg [16:0] d;
    wire [17:0] sh = {r, n[31]};
    wire        ge = sh >= {1'b0, d};

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) run <= 1'b0;
        else if (go) begin
            run <= 1'b1; cnt <= 6'd32; n <= num; d <= den; r <= 17'd0; q <= 32'd0;
        end else if (run) begin
            r <= ge ? sh - {1'b0, d} : sh[16:0];
            q <= {q[30:0], ge};
            n <= {n[30:0], 1'b0};
            cnt <= cnt - 6'd1;
            if (cnt == 6'd1) begin run <= 1'b0; done <= 1'b1; end
        end
    end
endmodule
