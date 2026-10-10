// The EDID reader bitstream minus its clocks, pins and serialiser (those are in
// rtl/board/edid_test_top.v): the machine's 800x600@60 timing, the DDC reader
// (rtl/board/edid_reader.v) and the hex screen (rtl/board/edid_text.v). Tested
// as a whole in CXXRTL against a C++ DDC EEPROM model (tests/tb/edid_core_tb.cpp).
`default_nettype none

module edid_core #(
    parameter integer QUARTER = 200,
    parameter integer PERIOD_BITS = 24
) (
    input  wire       clk,             // pixel clock, 40 MHz
    input  wire       rst,
    output wire       scl_low,         // DDC: 1 pulls the line low, 0 releases it
    output wire       sda_low,
    input  wire       scl_in,
    input  wire       sda_in,
    input  wire       hpd,
    output wire [7:0] r, g, b,
    output wire       de, hsync, vsync,
    output wire [7:0] ch,              // the character on screen at this pixel (tests)
    output wire [2:0] status,
    output wire [7:0] reads
);
    wire        t_hs, t_vs, t_de;
    wire [10:0] out_x;
    wire [9:0]  out_y;
    zm_vtiming u_t (.clk(clk), .rst(rst), .hsync(t_hs), .vsync(t_vs), .de(t_de), .out_x(out_x), .out_y(out_y),
                    .zm_active(), .zm_x(), .zm_line(), .zm_hbl(), .zm_hbl_line(), .zm_vbl());

    wire [7:0] rd_addr, rd_data, sum_data;
    wire [4:0] sum_addr;
    edid_reader #(.QUARTER(QUARTER), .PERIOD_BITS(PERIOD_BITS)) u_rd (
        .clk(clk), .rst(rst), .scl_low(scl_low), .sda_low(sda_low), .scl_in(scl_in), .sda_in(sda_in),
        .status(status), .reads(reads), .rd_addr(rd_addr), .rd_data(rd_data),
        .sum_addr(sum_addr), .sum_data(sum_data));

    reg [1:0] hpd_s = 2'b00;
    always @(posedge clk) hpd_s <= {hpd_s[0], hpd};
    edid_text u_txt (
        .clk(clk), .x(out_x), .y(out_y), .de(t_de), .hs(t_hs), .vs(t_vs),
        .status(status), .reads(reads), .hpd(hpd_s[1]),
        .rd_addr(rd_addr), .rd_data(rd_data), .sum_addr(sum_addr), .sum_data(sum_data),
        .r(r), .g(g), .b(b), .de_o(de), .hs_o(hsync), .vs_o(vsync), .ch(ch));
endmodule

`default_nettype wire
