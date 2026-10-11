// A channel's pixel address, base + (y - yorg) * stride + (x - xorg) modulo 2^23 (every
// address an op may touch is below 0x700000), with no multiplier between the sequencer's
// (x, y) and the pixel unit: the row address follows y instead of being computed from it.
// Every sequencer moves its y by at most one row a clock, and always the same way during
// an op (`dn`: BLIT DESC, a LINE drawn upwards), so the row it is on is either the one
// held here (`row`, at `ry`) or the next one (`nxt`, at `ry_nx`), already added; the pixel
// address is one add of x to that. y is signed (a LINE walks rows above the clip, whose
// address is never used); x is not negative for any pixel issued (the clip starts at 0
// and at the rectangle's own origin), so its sign extension is its value.
//
// The first row needs the product: the setup pipeline computes it from the op's first
// row `ys` (and the origin) in three clocks, free-running, and `ld` takes it. Its inputs
// are registers that hold still while the op runs; `ys` derives from zm_blit_chk's box,
// written three clocks before the core's `go` reaches the sequencers (CHK states 2 -> 5,
// then `go`), so the pipeline is full by then: zero clocks added per op. A path of
// register -> subtract -> DSP -> two adds missed 100 MHz by 0.45 ns in the full SoC with
// the FPU (Vivado, 2026-10-11).
`default_nettype none

module zm_blit_row (
    input  wire               clk,
    input  wire [22:0]        base,
    input  wire [15:0]        stride,
    input  wire signed [17:0] xorg, yorg,   // the pixel whose address is `base`
    input  wire signed [17:0] ys,           // the op's first row: settled 3 clocks before `ld`
    input  wire               dn,           // the op walks its rows towards smaller y
    input  wire               ld,           // the op starts: the sequencer's y is `ys` next clock
    input  wire signed [17:0] y, x,         // the sequencer's pixel
    output wire [22:0]        addr
);
    // setup, free-running: (ys - yorg) * stride + base - xorg, and the row step. Only the product
    // needs the three clocks; the rest is sampled at the last one (all of it settled by then).
    reg signed [17:0] s_j, s_y3;
    reg [22:0] s_row, s_str3;
    reg s_dn3;
    reg signed [35:0] s_prod;
    wire [22:0] str = {7'd0, stride};
    always @(posedge clk) begin
        s_j <= ys - yorg;
        s_prod <= s_j * $signed({2'b00, stride});
        s_row <= base - {{5{xorg[17]}}, xorg} + s_prod[22:0]; s_y3 <= ys; s_dn3 <= dn; s_str3 <= dn ? -str : str;
    end

    // the walk: the row the sequencer is on, or the next one
    reg signed [17:0] ry, ry_nx;
    reg [22:0] row, nxt, step;
    reg down;
    wire moved = y == ry_nx;
    wire [22:0] cur = moved ? nxt : row;
    assign addr = cur + {{5{x[17]}}, x};
    wire signed [17:0] ry_n = ld ? s_y3 : moved ? ry_nx : ry;
    wire [22:0] row_n = ld ? s_row : cur, step_n = ld ? s_str3 : step;
    wire down_n = ld ? s_dn3 : down;
    always @(posedge clk) begin
        ry <= ry_n; row <= row_n; step <= step_n; down <= down_n;
        ry_nx <= down_n ? ry_n - 18'sd1 : ry_n + 18'sd1;
        nxt <= row_n + step_n;
    end
endmodule
