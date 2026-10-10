// The samples' clock crossing: a 16-deep asynchronous FIFO from the system
// domain (zm_audio_core makes a sample) to the pixel domain (zm_hdmi_tx asks for
// one), Gray-coded pointers through two flops each way (Cummings, SNUG 2002).
// Both rates are exact fractions of clocks from one crystal, so the level only
// wanders by the phase between the two strobes: the reader waits until the FIFO
// holds HALF before its first read, then reads one a request. `underflow` (a
// request found it empty after the start) and `overflow` (a write found it
// full, the sample dropped) are sticky, and neither should ever happen.
`default_nettype none

module zm_audio_fifo #(
    parameter integer W = 32,
    parameter integer AW = 4               // 2^AW entries
) (
    input  wire         wclk,
    input  wire         wrst,
    input  wire         winc,
    input  wire [W-1:0] wdata,
    output reg          overflow = 1'b0,
    input  wire         rclk,
    input  wire         rrst,
    input  wire         rreq,              // a sample is due
    output reg          rvalid = 1'b0,     // the clock after rreq, when one was there
    output reg  [W-1:0] rdata = {W{1'b0}},
    output reg          underflow = 1'b0
);
    localparam [AW:0] HALF = 1 << (AW - 1);
    reg  [W-1:0] mem [0:(1 << AW) - 1];
    reg  [AW:0]  wbin = 0, wgray = 0, rbin = 0, rgray = 0;
    reg  [AW:0]  rg_w1 = 0, rg_w2 = 0, wg_r1 = 0, wg_r2 = 0;

    function [AW:0] g2b(input [AW:0] g);
        integer i;
        begin
            g2b[AW] = g[AW];
            for (i = AW - 1; i >= 0; i = i - 1) g2b[i] = g2b[i + 1] ^ g[i];
        end
    endfunction

    // --- write side
    wire [AW:0] wbin1 = wbin + 1'b1;
    wire        full = wgray == {~rg_w2[AW:AW - 1], rg_w2[AW - 2:0]};
    always @(posedge wclk) begin
        {rg_w2, rg_w1} <= {rg_w1, rgray};
        if (wrst) begin
            {wbin, wgray, overflow} <= 0;
        end else if (winc) begin
            if (full) overflow <= 1'b1;
            else begin
                mem[wbin[AW - 1:0]] <= wdata;
                wbin <= wbin1;
                wgray <= wbin1 ^ (wbin1 >> 1);
            end
        end
    end

    // --- read side
    wire [AW:0] level = g2b(wg_r2) - rbin;
    wire        empty = level == 0;
    reg         started = 1'b0;
    wire [AW:0] rbin1 = rbin + 1'b1;
    always @(posedge rclk) begin
        {wg_r2, wg_r1} <= {wg_r1, wgray};
        rvalid <= 1'b0;
        if (rrst) begin
            {rbin, rgray, started, underflow} <= 0;
        end else begin
            if (level >= HALF) started <= 1'b1;
            if (rreq && started && empty) underflow <= 1'b1;
            if (rreq && started && !empty) begin
                {rvalid, rdata} <= {1'b1, mem[rbin[AW - 1:0]]};
                rbin <= rbin1;
                rgray <= rbin1 ^ (rbin1 >> 1);
            end
        end
    end
endmodule

`default_nettype wire
