// The sound-chip lab's player (docs/FPGA_AUDIO.md): a register dump in a ROM,
// played into any chip through a register-write port, one frame a `tick`. The
// ROM format is tools/ym_rom.py's (16-bit words):
//   0rrrrrrr vvvvvvvv   write v to register r
//   1nnnnnnn nnnnnnnn   wait n frames (n >= 1)
//   0x8000, w           jump to word w (the loop)
// Exactly as tests/audio_ref/audio_ref.zig plays it: on a tick with no frames
// left to wait, the words run up to the next wait, whose n then counts this
// frame; on any other tick one frame of the wait passes. The parent ticks once
// at the start and then every 882 samples (50 Hz at 44.1 kHz), so the writes of
// frame k land just before sample 882 k is made. A write is held until the chip
// takes it (`chip_wr && chip_ready`).
`default_nettype none

module zm_dump_player #(
    parameter         ROM = "dump.hex",
    parameter integer WORDS = 1024,      // the ROM's depth (any; BRAM rounds it up)
    parameter integer AW = 16
) (
    input  wire          clk,
    input  wire          rst,
    input  wire          tick,
    output reg           chip_wr = 1'b0,
    output reg  [6:0]    chip_reg = 7'd0,
    output reg  [7:0]    chip_val = 8'd0,
    input  wire          chip_ready,
    output reg  [AW-1:0] pc = {AW{1'b0}}   // the next word: shows where the tune is
);
    reg [15:0] rom [0:WORDS - 1];
    initial $readmemh(ROM, rom);
    reg [15:0] word = 16'd0;
    always @(posedge clk) word <= rom[pc];      // a BRAM: one clock to read

    localparam [2:0] IDLE = 3'd0, READ = 3'd1, DECODE = 3'd2, JWAIT = 3'd3, JUMP = 3'd4, WRITE = 3'd5;
    reg [2:0]  st = IDLE;
    reg [14:0] wait_n = 15'd0;

    always @(posedge clk) begin
        if (rst) begin
            {st, wait_n, chip_wr, pc} <= 0;
        end else begin
            case (st)
                IDLE: if (tick) begin
                    if (wait_n == 15'd0) st <= READ;
                    else wait_n <= wait_n - 15'd1;
                end
                READ: st <= DECODE;                  // `word` is rom[pc] from the next clock
                DECODE: begin
                    pc <= pc + 1'b1;
                    if (word == 16'h8000) st <= JWAIT;
                    else if (word[15]) {wait_n, st} <= {word[14:0] - 15'd1, IDLE};
                    else {chip_wr, chip_reg, chip_val, st} <= {1'b1, word[14:8], word[7:0], WRITE};
                end
                JWAIT: st <= JUMP;                   // reading the target, at pc + 1
                JUMP: {pc, st} <= {word[AW-1:0], READ};
                WRITE: if (chip_ready) {chip_wr, st} <= {1'b0, READ};
                default: st <= IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
