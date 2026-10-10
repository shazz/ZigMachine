// Simulation only (soc/hp_sim.py): what the audio core does, to a file in the
// run directory, for tools/audio_sim_compare.py to hold against the native host
// (host/audio_soft.c writes the same lines):
//   "W now addr data"   a register write landing in zm_audio_core, at sample `now`
//   "S llll rrrr"       a stereo sample out of the core (hex, int16)
// Nothing here is synthesised; the board build never adds this file.
module zm_audio_tap #(
    parameter FILE = "audio_tap.txt"
) (
    input wire        clk,
    input wire        wr,
    input wire [9:0]  addr,
    input wire [31:0] data,
    input wire [31:0] now,
    input wire        smp_valid,
    input wire [15:0] smp_l,
    input wire [15:0] smp_r
);
    integer f;
    initial f = $fopen(FILE, "w");
    always @(posedge clk) begin
        if (wr) $fwrite(f, "W %0d %03x %08x\n", now, addr, data);
        if (smp_valid) $fwrite(f, "S %04x %04x\n", smp_l, smp_r);
    end
endmodule
