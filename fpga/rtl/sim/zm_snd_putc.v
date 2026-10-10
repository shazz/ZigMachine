// The sound CPU's console (soc/zm_sound_regs.py PUTC): each character written goes to
// the simulator's stdout, which the sim run keeps as uart.txt. Synthesis sees an empty
// module: on the board the sound CPU's printf goes nowhere.
module zm_snd_putc (
    input wire clk,
    input wire we,
    input wire [7:0] c
);
`ifndef SYNTHESIS
    always @(posedge clk) if (we) $write("%c", c);
`endif
endmodule
