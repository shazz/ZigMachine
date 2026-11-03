// PROTOTYPE check (TRUECOLOR_PLANE.md): the 565 painter picks the right half-word of each fetched word
// and expands it by bit replication into the doubled line-buffer pair. iverilog, no lock.
`timescale 1ns/1ps
module tb;
    reg clk = 0; always #4 clk = ~clk;
    reg rst = 1, start = 0, tc = 1;
    wire [7:0] fb_raddr, pal_raddr;
    reg  [31:0] fb_rdata, pal_rdata = 32'hDEADBEEF;
    wire lb_we_lo, lb_we_hi, done;
    wire [8:0] lb_addr;
    wire [31:0] lb_data;
    reg [31:0] mem [0:255];
    always @(posedge clk) fb_rdata <= mem[fb_raddr];
    zm_video_paint u (.clk(clk), .rst(rst), .start(start), .ncols(10'd8), .align(2'd0), .single(1'b0),
        .dst0(10'd80), .wrap(1'b0), .stride(16'd640), .s0(16'd0), .ov(1'b0), .band(1'b0), .band_open(1'b0),
        .hit(1'b0), .flick(1'b0), .tc(tc), .nbase(8'd0), .fb_raddr(fb_raddr), .fb_rdata(fb_rdata),
        .pal_raddr(pal_raddr), .pal_rdata(pal_rdata), .lb_we_lo(lb_we_lo), .lb_we_hi(lb_we_hi),
        .lb_addr(lb_addr), .lb_data(lb_data), .done(done));
    reg [15:0] px [0:7];
    function [31:0] expand(input [15:0] h);
        expand = {8'hFF, h[4:0], h[4:2], h[10:5], h[10:9], h[15:11], h[15:13]};
    endfunction
    integer i, n = 0, bad = 0;
    initial begin
        px[0] = 16'hF800; px[1] = 16'h07E0; px[2] = 16'h001F; px[3] = 16'h8410;
        px[4] = 16'hFFFF; px[5] = 16'h0000; px[6] = 16'h1234; px[7] = 16'hABCD;
        for (i = 0; i < 4; i = i + 1) mem[i] = {px[2*i+1], px[2*i]};   // little-endian pairs
        #20 rst = 0; #16 start = 1; #8 start = 0;
        repeat (40) @(posedge clk);
        if (n != 8) begin $display("FAIL: %0d writes", n); bad = 1; end
        if (bad) $display("FAIL"); else $display("PASS: 8 columns, expansion and half-word order right");
        $finish;
    end
    always @(posedge clk) if (lb_we_lo || lb_we_hi) begin
        if (!(lb_we_lo && lb_we_hi) || lb_addr != 40 + n || lb_data != expand(px[n])) begin
            $display("FAIL col %0d: we %b%b addr %0d data %08x want %08x", n, lb_we_lo, lb_we_hi, lb_addr, lb_data, expand(px[n])); bad = 1;
        end
        $display("col %0d addr %0d data %08x", n, lb_addr, lb_data);
        n = n + 1;
    end
endmodule
