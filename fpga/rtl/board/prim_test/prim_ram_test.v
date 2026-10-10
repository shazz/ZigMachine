// One block-RAM or LUTRAM mode of the primitive self-test (rtl/board/prim_test_top.v).
// The memory is INFERRED, written the way the SoC's RTL writes its memories, so
// Yosys picks the primitive and mode itself and the test checks what our flow
// produces: the depth, the width and the port style choose RAMB36/RAMB18 (SDP
// or TDP, at each width) or RAM32M/RAM64M.
//   STYLE 0 (SDP): a write port and a separate read port, each with its own address.
//   STYLE 1 (RF):  one port, read-first: a write returns the word it replaced.
//   STYLE 2 (WF):  one port, write-first: a write returns the word written.
// BW < DW gives each style a write enable per BW-bit byte (WEA/WEBWE bits).
// The memory has 2^MAW words; the test uses 2^AW of them from ABASE on, so a
// lane can live in one part of the address range (board evidence 2026-10-04:
// an SDP x36 RAMB18 failed with 256 words used, not with 512).
// A run is two passes: write every word (the LFSR's), read every word back;
// then the same with every bit inverted (with byte enables: only in the bytes
// an LFSR mask picks), so each bit of each word holds a 0 and a 1. On one port the writes
// are checked too: a WF write must return the word as written (its unwritten
// bytes old), a second-pass RF write the first pass's word. Every read is compared, one clock later, against a
// second LFSR reloaded with the same seed.
`default_nettype none

module prim_ram_test #(
    parameter integer AW = 9,
    parameter integer DW = 72,
    parameter integer STYLE = 0,
    parameter integer MAW = AW,
    parameter integer ABASE = 0,
    parameter integer BW = DW,
    parameter [95:0]  FLIP = 96'd0
) (
    input  wire         clk,
    input  wire         start,
    input  wire         clear,
    input  wire [31:0]  seed,
    output reg          done,
    output wire [223:0] res
);
    localparam integer D = 1 << AW;
    localparam integer NB = DW / BW;
    localparam [1:0] IDLE = 2'd0, WR = 2'd1, RD = 2'd2;
    localparam [MAW-1:0] BASE = ABASE;

    reg  [1:0]    phase = IDLE;
    initial done = 1'b0;
    reg           pass;
    reg  [AW-1:0] wa, ra;  // two counters: an SDP RAM needs two address nets
    wire [AW-1:0] a = (STYLE == 0 || STYLE == 3 || phase == WR) ? wa : ra;
    wire [MAW-1:0] pa = BASE | a, pwa = BASE | wa, pra = BASE | ra;
    wire          wlast = wa == D - 1, rlast = ra == D - 1;
    wire          we = phase == WR;
    wire          reload = start || (we && wlast) || (phase == RD && rlast && !pass);
    wire [DW-1:0] gq;
    wire [DW-1:0] wd = gq ^ {DW{pass}};
    prim_lfsr #(.W(DW)) gen (.clk(clk), .load(reload), .seed(seed), .step(phase != IDLE), .q(gq));

    // --- with byte enables, the second pass writes only the bytes its mask picks
    wire [NB-1:0] mask;
    wire [DW-1:0] mbits;
    genvar b;
    generate
        for (b = 0; b < NB; b = b + 1) begin : byte_mask
            assign mask[b] = gq[b * BW] ^ gq[(b * BW + 1) % DW];
            assign mbits[b * BW +: BW] = {BW{mask[b]}};
        end
    endgenerate
    wire [NB-1:0] be = (pass && BW < DW) ? mask : {NB{1'b1}};
    wire [DW-1:0] flips = BW < DW ? mbits : {DW{1'b1}};

    // --- the memory under test
    reg [DW-1:0] mem [0:(1 << MAW) - 1];
    reg [DW-1:0] rd;
    integer j;
    generate
        if (BW == DW && STYLE == 0) begin : sdp
            always @(posedge clk) if (we) mem[pwa] <= wd;
            always @(posedge clk) rd <= mem[pra];
        end else if (BW == DW && STYLE == 1) begin : rf
            always @(posedge clk) begin
                if (we) mem[pa] <= wd;
                rd <= mem[pa];
            end
        end else if (BW == DW) begin : wf
            always @(posedge clk)
                if (we) begin
                    mem[pa] <= wd;
                    rd <= wd;
                end else rd <= mem[pa];
        end else if (STYLE == 0) begin : sdp_be
            always @(posedge clk)
                for (j = 0; j < NB; j = j + 1)
                    if (we && be[j]) mem[pwa][j * BW +: BW] <= wd[j * BW +: BW];
            always @(posedge clk) rd <= mem[pra];
        end else if (STYLE == 1) begin : rf_be
            always @(posedge clk) begin
                for (j = 0; j < NB; j = j + 1)
                    if (we && be[j]) mem[pa][j * BW +: BW] <= wd[j * BW +: BW];
                rd <= mem[pa];
            end
        end else begin : wf_be
            always @(posedge clk)
                for (j = 0; j < NB; j = j + 1)
                    if (we && be[j]) begin
                        mem[pa][j * BW +: BW] <= wd[j * BW +: BW];
                        rd[j * BW +: BW] <= wd[j * BW +: BW];
                    end else rd[j * BW +: BW] <= mem[pa][j * BW +: BW];
        end
    endgenerate

    // --- what each read must return, one clock later
    wire          wr_check = we && (STYLE == 2 || (STYLE == 1 && pass));
    reg           v1;
    reg  [DW-1:0] exp1;
    reg  [31:0]   idx1;
    always @(posedge clk) begin
        v1 <= (phase == RD) || wr_check;
        // an RF write returns pass 1's word (gq); a WF write and a read, the word as last written
        exp1 <= (we && STYLE == 1) ? gq : gq ^ ({DW{pass}} & flips);
        idx1 <= {pass, we, {(30 - AW){1'b0}}, a};
    end
    prim_check #(.W(DW), .FLIP(FLIP)) chk (.clk(clk), .clear(clear), .v(v1), .got(rd), .exp(exp1), .idx(idx1), .res(res));

    // --- the sequence: WR, RD (pass 0), WR, RD (pass 1), IDLE
    always @(posedge clk) begin
        if (start) begin
            {phase, pass, wa, ra, done} <= {WR, 1'b0, {AW{1'b0}}, {AW{1'b0}}, 1'b0};
        end else if (we) begin
            wa <= wa + 1'b1;
            if (wlast) phase <= RD;
        end else if (phase == RD) begin
            ra <= ra + 1'b1;
            if (rlast) {phase, pass} <= pass ? {IDLE, 1'b0} : {WR, 1'b1};
        end else if (!v1) done <= 1'b1;
    end
endmodule

`default_nettype wire
