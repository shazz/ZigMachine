// The pixel unit: one destination pixel at a time. It reads the channels the minterm
// actually depends on (a minterm that ignores A, B or C never causes that read, which is
// invisible: reads have no side effects), computes D = LF(A,B,C) per bit, and writes the
// byte. A pixel whose B equals the key (KEY_EN) is not written and not counted.
//
// Memory ports (one word = 32 bits, the byte lane is addr[1:0]): single accesses, one read
// in flight per channel request, responses in request order at least one clock later with
// no back-pressure; a write is taken on wr_req_valid && wr_req_ready and a read issued
// after it sees it. Bursts would help here: a BLIT row is W consecutive bytes per channel.
//
// A pixel the minterm cannot change touches no memory: channel C only (no A, no B, no key)
// and LF(0, b, c) == c for every bit b of the constant B, e.g. a halftone's background
// bit OR'd (the glenz's rows of the other object) or XOR'd into the destination. Reading
// the byte and writing it back unchanged leaves memory as it was, so the pixel is counted
// (CYCLES is pixels written) and passed in one clock instead of a read and a write.
`default_nettype none

module zm_blit_px (
    input  wire              clk,
    input  wire              rst,
    input  wire              px_valid,
    output wire              px_ready,
    input  wire [22:0]       px_dst,          // linear byte address of the destination pixel (= channel C)
    input  wire [22:0]       px_aaddr, px_baddr,
    input  wire [7:0]        px_bimm,         // B when channel B is not read (a constant colour, or 0)
    input  wire [7:0]        px_mt, px_key,
    input  wire [3:0]        px_flags,        // {KEY_EN, USEC, USEB, USEA}
    output wire              px_idle,
    output wire              wrote,           // a byte was written this clock
    output wire              rd_req_valid,
    input  wire              rd_req_ready,
    output wire [31:0]       rd_req_addr,
    input  wire              rd_rsp_valid,
    input  wire [31:0]       rd_rsp_data,
    output wire              wr_req_valid,
    input  wire              wr_req_ready,
    output wire [31:0]       wr_req_addr,
    output wire [31:0]       wr_req_data,
    output wire [3:0]        wr_req_strb
);
    localparam [1:0] IDLE = 2'd0, READ = 2'd1, WRITE = 2'd2;
    reg [1:0]  st;
    reg [22:0] dst, aaddr, baddr;
    reg [7:0]  bimm, mt, key;
    reg        ben, keyen, nop;
    reg [2:0]  pend, iss, got;   // channels still to request / requested / answered: {C,B,A}
    reg [7:0]  a_v, b_v, c_v;

    function [2:0] need(input [7:0] m, input aen, ben, cen, ken);
        reg a_dc, b_dc, c_dc;
        begin
            a_dc = m[3:0] == m[7:4];
            b_dc = m[1:0] == m[3:2] && m[5:4] == m[7:6];
            c_dc = m[0] == m[1] && m[2] == m[3] && m[4] == m[5] && m[6] == m[7];
            need = {cen && !c_dc, ben && (ken || !b_dc), aen && !a_dc};
        end
    endfunction

    // LF(0, b, c) == c for each bit b of `b`: m[{0,0,c}] == c where b has a 0, m[{0,1,c}] == c where a 1
    function ident(input [7:0] m, input [7:0] b);
        ident = (&b || (!m[0] && m[1])) && (~|b || (!m[2] && m[3]));
    endfunction

    wire [7:0] bval = ben ? b_v : bimm;
    wire skip = keyen && bval == key;
    wire w_st = st == WRITE;
    assign px_ready = st == IDLE || (w_st && (skip || nop || wr_req_ready));
    assign px_idle = st == IDLE;
    wire acc = px_valid && px_ready;
    assign wrote = w_st && !skip && (nop || wr_req_ready);
    wire [2:0] nd = need(px_mt, px_flags[0], px_flags[1], px_flags[2], px_flags[3]);
    wire px_nop = px_flags == 4'b0100 && ident(px_mt, px_bimm);

    wire [2:0] low = pend & (~pend + 3'd1);
    assign rd_req_valid = st == READ && pend != 3'd0;
    assign rd_req_addr = {9'd0, low[0] ? aaddr : low[1] ? baddr : dst};
    wire [2:0] out = iss & ~got;
    wire [2:0] rl = out & (~out + 3'd1);
    wire [22:0] raddr = rl[0] ? aaddr : rl[1] ? baddr : dst;
    wire [7:0] rbyte = rd_rsp_data >> {raddr[1:0], 3'b000};

    wire [7:0] res;
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : lf
            assign res[i] = mt[{a_v[i], bval[i], c_v[i]}];
        end
    endgenerate
    assign wr_req_valid = w_st && !skip && !nop;
    assign wr_req_addr = {9'd0, dst[22:2], 2'b00};
    assign wr_req_data = {4{res}};
    assign wr_req_strb = 4'b0001 << dst[1:0];

    always @(posedge clk) begin
        if (rst) st <= IDLE;
        else begin
            if (st == READ) begin
                if (rd_req_valid && rd_req_ready) begin pend <= pend & ~low; iss <= iss | low; end
                if (rd_rsp_valid) begin
                    got <= got | rl;
                    if (rl[0]) a_v <= rbyte;
                    if (rl[1]) b_v <= rbyte;
                    if (rl[2]) c_v <= rbyte;
                end
                if (pend == 3'd0 && iss == got) st <= WRITE;
            end else if (w_st && (skip || nop || wr_req_ready)) st <= IDLE;
            if (acc) begin
                dst <= px_dst; aaddr <= px_aaddr; baddr <= px_baddr; bimm <= px_bimm; mt <= px_mt; key <= px_key;
                ben <= px_flags[1]; keyen <= px_flags[3]; nop <= px_nop;
                pend <= px_nop ? 3'd0 : nd; iss <= 3'd0; got <= 3'd0;
                a_v <= 8'd0; b_v <= 8'd0; c_v <= 8'd0;
                st <= px_nop || nd == 3'd0 ? WRITE : READ;
            end
        end
    end
endmodule
