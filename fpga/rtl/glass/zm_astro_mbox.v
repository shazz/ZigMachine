// ASTROLABE's mailbox (SPIKE, docs/ARM_FPU_COPROC.md): one block RAM both CPUs see.
//
// 1024 words (4 KiB, one RAMB36). Port A is ZIGGY's, a Wishbone classic slave in an uncached
// window (soc/zm_astro.py): one access at a time, acked the clock after the strobe with the
// word read then. Port B is the ARM's, reached through the glass block on M_AXI_GP0
// (zm_glass_regs.v forwards the ASTRO range): a write, or a read whose word comes the clock
// after `arm_re`. Both ports are in sys and the RAM is READ_FIRST: a read that meets the other
// port's write of the same word returns the old word whole, never a torn one. The protocol
// (cycles/bastro.c, glass/src/astro.zig) gives every word one writer, so a reader can only be
// early, and polls again.
//
// No logic beyond the RAM and the ack: no LUTs for registers, no DSP.
`default_nettype none

module zm_astro_mbox #(
    parameter integer AW = 10
) (
    input  wire          clk,
    input  wire          rst,
    // ZIGGY: Wishbone classic, word addressed
    input  wire          wb_cyc,
    input  wire          wb_stb,
    input  wire          wb_we,
    input  wire [AW-1:0] wb_adr,
    input  wire [31:0]   wb_dat_w,
    input  wire [3:0]    wb_sel,
    output reg           wb_ack,
    output reg  [31:0]   wb_dat_r,
    // the ARM, from zm_glass_regs: a write, or a read answered on arm_rdata the next clock
    input  wire          arm_we,
    input  wire [AW-1:0] arm_waddr,
    input  wire [31:0]   arm_wdata,
    input  wire [3:0]    arm_wstrb,
    input  wire          arm_re,
    input  wire [AW-1:0] arm_raddr,
    output reg  [31:0]   arm_rdata
);
    (* ram_style = "block" *) reg [31:0] mem [0:(1 << AW) - 1];

    wire          a_go = wb_cyc && wb_stb && !wb_ack;
    wire          a_we = a_go && wb_we;
    wire [AW-1:0] b_adr = arm_we ? arm_waddr : arm_raddr;
    integer i;

    // Port A: ZIGGY. The read happens on every strobe (a write's read is ignored).
    always @(posedge clk) begin
        if (a_go) wb_dat_r <= mem[wb_adr];
        for (i = 0; i < 4; i = i + 1)
            if (a_we && wb_sel[i]) mem[wb_adr][i * 8 +: 8] <= wb_dat_w[i * 8 +: 8];
    end
    always @(posedge clk) wb_ack <= !rst && a_go;

    // Port B: the ARM. A write wins the port; zm_glass_regs never issues both in one clock.
    always @(posedge clk) begin
        if (arm_re && !arm_we) arm_rdata <= mem[b_adr];
        for (i = 0; i < 4; i = i + 1)
            if (arm_we && arm_wstrb[i]) mem[b_adr][i * 8 +: 8] <= arm_wdata[i * 8 +: 8];
    end
endmodule

`default_nettype wire
