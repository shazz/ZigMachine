// The OSD test's power-on text (rtl/board/osd_test_top.v): after reset it
// writes all 512 cells of zm_glass_osd's text RAM, one a clock, through the
// same write port the ARM's register block uses. So the overlay shows a known
// screen before the ARM has touched GP0, and proves itself even if GP0 never
// answers. A reset (the PLL relocking) writes it again, over the ARM's text.
//
//   row  0       the title, inverse
//   row  2, 3    what this is
//   rows 4..11   every glyph of the font, 0x00..0xFF, 32 a row
//   row 13, 14   where the ARM finds the block, and what it should read
//   row 15       the board, inverse
`default_nettype none

module osd_banner (
    input  wire       clk,
    input  wire       rst,
    output reg        we = 1'b0,
    output reg  [8:0] waddr = 9'd0,
    output reg  [8:0] wdata = 9'd0,
    output wire       busy              // the banner is still being written
);
    function [8:0] banner_cell(input [8:0] a);
        reg [255:0] line;
        begin
            case (a[8:5])
                4'd0:  line = "      ZIGMACHINE OSD TEST       ";
                4'd2:  line = " THE PL WROTE THIS AT POWER-ON  ";
                4'd3:  line = " THE FONT, CHARACTERS 00-FF:    ";
                4'd13: line = " GP0 43C00000  ID 5A4D474C      ";
                4'd14: line = " WAITING FOR THE ARM (U-BOOT)   ";
                4'd15: line = "  MICROPHASE Z7-LITE  XC7Z010   ";
                default: line = {32{8'h20}};
            endcase
            if (a[8:5] >= 4'd4 && a[8:5] < 4'd12) banner_cell = {1'b0, a[7:0] ^ 8'h80};  // cell 128 = glyph 0
            else banner_cell = {a[8:5] == 4'd0 || a[8:5] == 4'd15, line[8 * (31 - a[4:0]) +: 8]};
        end
    endfunction

    reg [9:0] n = 10'd0;  // the next cell; bit 9 set = done
    assign busy = !n[9] || we;
    always @(posedge clk) begin
        if (rst) n <= 10'd0;
        else if (!n[9]) n <= n + 10'd1;
        we <= !rst && !n[9];
        waddr <= n[8:0];
        wdata <= banner_cell(n[8:0]);
    end
endmodule

`default_nettype wire
