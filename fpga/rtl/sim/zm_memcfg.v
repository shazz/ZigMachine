// Simulation only: the cycles sim's memory-path parameters (soc/zm_memtiming.py),
// read at time 0 from FILE (zm_memcfg.init) in the run directory (tools/cycles_sim.sh
// writes it), so one Verilated model runs every memory configuration. One hex
// word per line, in the order of zm_memtiming.CFG; a missing word reads as 0.
// The video sim (soc/video_sim.py) reads a second one, zm_dmacfg.init, for the
// video DMA's path.
module zm_memcfg #(
    parameter FILE = "zm_memcfg.init"
) (
    output wire [511:0] cfg
);
    reg [31:0] words [0:15];
    integer i;
    initial begin
        for (i = 0; i < 16; i = i + 1) words[i] = 32'd0;
        $readmemh(FILE, words);
    end
    genvar g;
    generate
        for (g = 0; g < 16; g = g + 1) begin : w
            assign cfg[g*32 +: 32] = words[g];
        end
    endgenerate
endmodule
