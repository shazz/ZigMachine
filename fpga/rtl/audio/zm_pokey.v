// The Atari POKEY (C012294), its AUDIO half: four channels, AUDF/AUDC, AUDCTL,
// STIMER, SKCTL's init mode. Written from scratch from public documentation
// (the Altirra Hardware Reference Manual's POKEY chapter, Atari's C012294 data
// sheet, De Re Atari ch. 7); no MAME, ASAP or GPL HDL was read or ported.
// machine/audio/pokey.zig is the reference model: the testbench
// (tests/test_rtl_pokey.py) requires the four levels to match it, bit for bit,
// every machine cycle.
//
// NOT here: IRQs, the serial port, keyboard scan, pots, RANDOM / any read, and
// two-tone mode. The chip's non-linear analog mixer is the plain sum `mix`.
//
// The machine cycle is `cen`, a fractional enable from the system clock, NTSC
// or PAL by `pal` (the SAP's NTSC tag): 315/176 MHz (NTSC, 1789772.7 Hz) =
// 100 MHz x 63 / 3520, or 1773447.495 Hz (PAL, 0.003 ppm under the real
// 1773447.5) = 100 MHz x 901 / 50805; the model's Clock is the same two ratios.
// Change `pal` only between tunes: switching mid-run is not modelled. Each cen cycle, in
// order: the channels count, sampling the polys as they were before it; the
// high-pass latches take the outputs as they were before it; the polys shift.
// Register writes (`we`, one a clock) land between machine cycles; a write in a
// clock where `cen` is high lands after that cycle. Writes: 0/2/4/6 AUDF1-4,
// 1/3/5/7 AUDC1-4, 8 AUDCTL, 9 STIMER (any data), F SKCTL; others ignored.
// `level` and `mix` are registered: they show the state one clock after it.
`default_nettype none

module zm_pokey #(
    parameter integer CEN_INC = 63,
    parameter integer CEN_MOD = 3520,
    parameter integer PAL_INC = 901,
    parameter integer PAL_MOD = 50805
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        pal,            // 1: the PAL machine clock
    input  wire        we,
    input  wire [3:0]  addr,
    input  wire [7:0]  din,
    output wire        cen,            // the machine cycle (for a box filter)
    output reg  [15:0] level = 16'd0,  // channel n in bits 4(n-1)+3 .. 4(n-1)
    output reg  [5:0]  mix = 6'd0      // the four levels summed, 0..60
);
    wire cen_ntsc, cen_pal;
    zm_audio_frac #(.INC(CEN_INC), .MOD(CEN_MOD)) u_cen (.clk(clk), .rst(rst), .tick(cen_ntsc));
    zm_audio_frac #(.INC(PAL_INC), .MOD(PAL_MOD)) u_pal (.clk(clk), .rst(rst), .tick(cen_pal));
    assign cen = pal ? cen_pal : cen_ntsc;

    reg [7:0] audf [0:3];
    reg [7:0] audc [0:3];
    reg [7:0] audctl = 8'd0;
    reg [1:0] skctl = 2'd0;            // power-up: init mode; the OS writes 3
    reg [4:0] div28 = 5'd0;
    reg [6:0] div114 = 7'd0;
    reg [3:0] out = 4'd0;              // the output flip-flops
    reg [1:0] hp = 2'd0;               // the high-pass latches of channels 1, 2
    integer i, j, k;                   // one loop index per process
    initial for (i = 0; i < 4; i = i + 1) {audf[i], audc[i]} = 16'd0;

    wire init = skctl == 2'b00;
    wire stimer = we && addr == 4'h9;
    wire t64 = !init && div28 == 5'd27;
    wire t15 = !init && div114 == 7'd113;
    wire base = audctl[0] ? t15 : t64;

    // Init mode holds the polys at 0; gating their outputs too makes a cycle
    // that starts init in the same clock see them cleared, as the model does.
    wire q4, q5, q17;
    zm_pokey_poly u_poly (.clk(clk), .clr(rst || init), .cen(cen), .nine(audctl[7]),
        .p4(q4), .p5(q5), .p17(q17));
    wire p4 = q4 && !init, p5 = q5 && !init, p17 = q17 && !init;

    wire [3:0] b;
    zm_pokey_pair u_12 (.clk(clk), .rst(rst), .cen(cen), .stimer(stimer), .joined(audctl[4]),
        .tick_lo(audctl[6] || base), .tick_hi(base), .f_lo(audf[0]), .f_hi(audf[1]), .b_lo(b[0]), .b_hi(b[1]));
    zm_pokey_pair u_34 (.clk(clk), .rst(rst), .cen(cen), .stimer(stimer), .joined(audctl[3]),
        .tick_lo(audctl[5] || base), .tick_hi(base), .f_lo(audf[2]), .f_hi(audf[3]), .b_lo(b[2]), .b_hi(b[3]));

    // The output flip-flop on a borrow, per AUDC bits 7-5: bit 7 clear gates the
    // borrow with the 5-bit poly; bit 5 set toggles (pure tone); else the output
    // takes the 4-bit poly (bit 6) or the 17/9-bit poly.
    function automatic next_out(input o, input [7:0] c, input b4, input b5, input b17);
        if (!c[7] && !b5) next_out = o;
        else if (c[5]) next_out = !o;
        else if (c[6]) next_out = b4;
        else next_out = b17;
    endfunction

    // Volume while the output is high (always, volume-only); 1 and 2 through
    // their high-pass latch, an XOR held at 0 while the filter is off.
    function automatic [3:0] lvl(input o, input [7:0] c);
        lvl = (c[4] || o) ? c[3:0] : 4'd0;
    endfunction

    wire [3:0] l1 = lvl(out[0] ^ hp[0], audc[0]), l2 = lvl(out[1] ^ hp[1], audc[1]);
    wire [3:0] l3 = lvl(out[2], audc[2]), l4 = lvl(out[3], audc[3]);

    always @(posedge clk) begin
        level <= {l4, l3, l2, l1};
        mix <= {2'd0, l1} + {2'd0, l2} + {2'd0, l3} + {2'd0, l4};
    end

    always @(posedge clk) begin
        if (rst) begin
            for (j = 0; j < 4; j = j + 1) {audf[j], audc[j]} <= 16'd0;
            {audctl, skctl} <= 0;
        end else if (we) begin
            case (addr)
                4'h0, 4'h2, 4'h4, 4'h6: audf[addr[2:1]] <= din;
                4'h1, 4'h3, 4'h5, 4'h7: audc[addr[2:1]] <= din;
                4'h8: audctl <= din;
                4'hF: skctl <= din[1:0];
                default: ;
            endcase
        end
    end

    always @(posedge clk) begin
        if (rst || init) begin
            {div28, div114} <= 0;
        end else if (cen) begin
            div28 <= t64 ? 5'd0 : div28 + 5'd1;
            div114 <= t15 ? 7'd0 : div114 + 7'd1;
        end
    end

    always @(posedge clk) begin
        if (rst || stimer) begin
            {out, hp} <= 0;
        end else if (cen) begin
            for (k = 0; k < 4; k = k + 1)
                if (b[k]) out[k] <= next_out(out[k], audc[k], p4, p5, p17);
            hp[0] <= !audctl[2] ? 1'b0 : b[2] ? out[0] : hp[0];
            hp[1] <= !audctl[1] ? 1'b0 : b[3] ? out[1] : hp[1];
        end
    end
endmodule

`default_nettype wire
