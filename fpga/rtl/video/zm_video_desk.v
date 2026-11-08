// The desk mode's state beside the compositor (HW 1.17.0, RESOLUTION = RES_DESK,
// docs/GEM_DESK_MODE.md): what the scanout needs to show plane 0 itself, taken
// from the CPU's stores (the snoop, as zm_video_comp.v takes them), so the
// compositor's netlist does not change.
//
// - `desk_req`: RESOLUTION == RES_DESK, a level (a store of byte 0 of word 0).
//   Overscan carts flicker RESOLUTION between 0 and 2 mid-frame; only its value
//   at the VBL counts: zm_vtiming.v samples the synchronised level there
//   (`desk_shown`), and that sampled mode comes back here (`desk`) for the
//   scanout fetch, which samples it after the VBL has crossed too.
// - `desk_base`: plane 0's bus address, vbase + FB_BASE[0] with its low three
//   bits dropped (a beat; the machine renders from FB_BASE & ~7 too). A store
//   may change one byte lane of FB_BASE, as on the CPU side.
// - The mirror of palette 0 (256 x {B, G, R}, byte lanes): written from the same
//   stores as the compositor's palette (alpha is ignored), read by the scanout
//   in the pixel clock. The BRAM's two ports are the crossing, as the display
//   buffers'. The copper writes the compositor's palette directly, but no copper
//   list runs in desk mode, and ZigOS rewrites palette 0 when it enters it.
`default_nettype none

module zm_video_desk (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] vbase,
    input  wire        cpu_we,
    input  wire [20:0] cpu_waddr,
    input  wire [3:0]  cpu_be,
    input  wire [31:0] cpu_wdata,
    input  wire [2:0]  cpu_sel,          // {BEAM table, palettes, register block}
    output wire [31:0] desk_base,
    output wire        desk,             // the mode of the frame being shown, in clk's domain
    input  wire        pix_clk,
    output wire        desk_req_p,       // RES_DESK requested, in pix_clk's domain
    input  wire        desk_shown,       // zm_vtiming's sampled mode (pix_clk)
    input  wire [7:0]  pal_raddr,
    output wire [23:0] pal_rdata
);
`include "zm_video_memmap.vh"

    localparam [4:0] W_RES = ZM_REG_RESOLUTION / 4, W_FB0 = ZM_REG_FB_BASE / 4;
    localparam integer PAL_W = ZM_OFF_PAL / 4;
    wire reg_we = cpu_we && cpu_sel[0];
    wire [10:0] pal_idx = cpu_waddr[10:0] - PAL_W[10:0];   // within the 4 palettes when cpu_sel[1]

    reg desk_req = 1'b0;
    reg [31:0] fb0 = 32'd0;
    integer i;
    always @(posedge clk) begin
        if (rst) desk_req <= 1'b0;
        else if (reg_we && cpu_waddr[4:0] == W_RES && cpu_be[0]) desk_req <= cpu_wdata[7:0] == ZM_RES_DESK;
        for (i = 0; i < 4; i = i + 1)
            if (reg_we && cpu_waddr[4:0] == W_FB0 && cpu_be[i]) fb0[i * 8 +: 8] <= cpu_wdata[i * 8 +: 8];
    end
    assign desk_base = vbase + {fb0[31:3], 3'b000};

    // The request into the pixel clock, the shown mode back: levels, two flip-flops each. Each
    // changes at most once a frame, and the shown one only at the VBL (zm_vtiming.v).
    (* ASYNC_REG = "TRUE" *) reg [1:0] req_s = 2'b00;
    (* ASYNC_REG = "TRUE" *) reg [1:0] shown_s = 2'b00;
    always @(posedge pix_clk) req_s <= {req_s[0], desk_req};
    always @(posedge clk) shown_s <= {shown_s[0], desk_shown};
    assign desk_req_p = req_s[1];
    assign desk = shown_s[1];

    wire pal0_we = cpu_we && cpu_sel[1] && pal_idx[9:8] == 2'd0;
    zm_video_dcram #(.AW(8), .DW(24), .LW(8)) u_mirror (.wclk(clk), .we({3{pal0_we}} & cpu_be[2:0]),
        .waddr(pal_idx[7:0]), .wdata(cpu_wdata[23:0]), .rclk(pix_clk), .raddr(pal_raddr), .rdata(pal_rdata));
endmodule

`default_nettype wire
