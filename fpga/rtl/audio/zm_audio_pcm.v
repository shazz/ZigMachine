// The four Paula channels of machine/audio/engine.zig (Channel.mixInto), one
// sample at a time, time-shared through ONE multiplier, in integers that equal
// the engine's f32 arithmetic exactly:
//   s = data[pos >> 16] / 128, gain = 0.5 x volume x min(1, 1 -/+ pan)
// with volume = VOL / 256 and pan = PAN / 128 (the register forms, docs/FPGA_AUDIO.md)
// is, in units of 2^-23, s8 x VOL x min(128, 128 -/+ PAN). For VOL 0..256 and
// PAN -128..128 every f32 product and partial sum of the engine is exact (at
// most 22 significant bits, sums below 2^24 units), so the two agree bit for bit.
// Per channel and sample, as the engine: skip it when inactive or empty; when
// looping (LOOP_LEN > 1) wrap pos back by LOOP_LEN while past the loop's end,
// else stop the channel at the data's end; read the byte; mix; pos += STEP.
// The wrap subtracts once a clock, at most 255 times a sample (`overrun` pulses
// past that: a STEP of more than 255 loops a sample).
// Register writes (`we`, channel `wch`, field `wf`, see zm_audio_core) land
// between samples; a write to a channel's POS or CTRL while that channel is
// being mixed wins over the mix's own update (it happened after the sample).
`default_nettype none

module zm_audio_pcm (
    input  wire               clk,
    input  wire               rst,
    input  wire               we,
    input  wire [1:0]         wch,
    input  wire [3:0]         wf,
    input  wire [31:0]        wd,
    input  wire               silence,       // machineAudioReset: every channel stopped
    output reg  [31:0]        rd,            // the field `wf` of channel `wch`
    input  wire               start,         // mix one sample
    output reg                done = 1'b0,   // acc_l / acc_r hold it
    output reg  signed [27:0] acc_l = 28'sd0,
    output reg  signed [27:0] acc_r = 28'sd0,
    output reg                overrun = 1'b0,  // a pulse
    output reg                mem_req = 1'b0,  // read the byte at mem_addr: held until mem_ack
    output reg  [31:0]        mem_addr = 32'd0,
    input  wire               mem_ack,
    input  wire [7:0]         mem_data
);
    reg [31:0] base [0:3], sbase [0:3], step [0:3];
    reg [23:0] len [0:3], ls [0:3], ll [0:3], slen [0:3], sls [0:3], sll [0:3];
    reg [39:0] pos [0:3];
    reg [8:0]  vol [0:3], pan [0:3];
    reg [3:0]  active = 4'd0;

    localparam [3:0] IDLE = 4'd0, CHK = 4'd1, WRAP = 4'd2, FETCH = 4'd3, M1 = 4'd4, M2 = 4'd5, M3 = 4'd6,
                     M4 = 4'd7, NEXT = 4'd8;
    reg [3:0]  st = IDLE;
    reg [1:0]  c = 2'd0;
    reg [39:0] p = 40'd0;
    reg [7:0]  iter = 8'd0;
    reg signed [7:0]  s = 8'sd0;
    reg signed [17:0] gl = 18'sd0, gr = 18'sd0;

    // min(128, 128 - PAN) and min(128, 128 + PAN), PAN signed.
    wire signed [10:0] pan_c = $signed({pan[c][8], pan[c][8], pan[c]});
    wire signed [10:0] m_l0 = 11'sd128 - pan_c, m_r0 = 11'sd128 + pan_c;
    wire signed [10:0] m_l = (m_l0 > 11'sd128) ? 11'sd128 : m_l0;
    wire signed [10:0] m_r = (m_r0 > 11'sd128) ? 11'sd128 : m_r0;

    // The one multiplier: VOL x m in M1/M2, s x gain in M3/M4.
    wire        gains = st == M1 || st == M2;
    wire signed [17:0] mx = gains ? $signed({9'd0, vol[c]}) : {{10{s[7]}}, s};
    wire signed [17:0] my = (st == M1) ? {{7{m_l[10]}}, m_l} : (st == M2) ? {{7{m_r[10]}}, m_r}
                          : (st == M3) ? gl : gr;
    wire signed [35:0] prod = mx * my;

    wire        looping = ll[c] > 24'd1;
    wire [24:0] ls_ll = {1'b0, ls[c]} + {1'b0, ll[c]};
    wire [40:0] loop_end = {ls_ll, 16'd0};
    wire [39:0] span = {ll[c], 16'd0};
    // A bus write to channel c since CHK, per field the mix also updates: `pos`
    // (POS, or TRIGGER: then the mix's pos += STEP is dropped) and `act` (CTRL:
    // then its end-of-data stop is dropped). Each happened after the sample.
    wire        hit_pos = we && wch == c && (wf == 4'd7 || (wf == 4'd8 && wd[1]));
    wire        hit_act = we && wch == c && wf == 4'd8;
    wire        busy = st != IDLE;
    reg  [1:0]  dirty = 2'b00;               // {act, pos}

    always @(*) begin
        case (wf)
            4'd0: rd = sbase[wch];           4'd1: rd = {8'd0, slen[wch]};
            4'd2: rd = {8'd0, sls[wch]};     4'd3: rd = {8'd0, sll[wch]};
            4'd4: rd = step[wch];            4'd5: rd = {23'd0, vol[wch]};
            4'd6: rd = {{23{pan[wch][8]}}, pan[wch]};
            4'd7: rd = {8'd0, pos[wch][39:16]};
            4'd8: rd = {31'd0, active[wch]};
            default: rd = 32'd0;
        endcase
    end

    // Bus writes. TRIGGER (CTRL bit 1) is machinePaulaTrigger: the staged DATA,
    // LEN, LOOP_START, LOOP_LEN go live, pos 0, active.
    always @(posedge clk) begin
        if (we) begin
            case (wf)
                4'd0: sbase[wch] <= wd;            4'd1: slen[wch] <= wd[23:0];
                4'd2: sls[wch] <= wd[23:0];        4'd3: sll[wch] <= wd[23:0];
                4'd4: step[wch] <= wd;             4'd5: vol[wch] <= wd[8:0];
                4'd6: pan[wch] <= wd[8:0];
                default: ;
            endcase
            if (wf == 4'd8 && wd[1]) begin
                {base[wch], len[wch], ls[wch], ll[wch]} <= {sbase[wch], slen[wch], sls[wch], sll[wch]};
            end
        end
    end

    // pos and active: the mix's update, then the bus's (which wins).
    wire mix_wb = st == M4 && !dirty[0] && !hit_pos;
    wire mix_stop = st == WRAP && !looping && p >= {len[c], 16'd0} && !dirty[1] && !hit_act;
    always @(posedge clk) begin
        if (mix_wb) pos[c] <= p + {8'd0, step[c]};
        if (mix_stop) active[c] <= 1'b0;
        if (we && wf == 4'd7) pos[wch] <= {wd[23:0], 16'd0};
        if (we && wf == 4'd8) active[wch] <= wd[1] | wd[0];
        if (we && wf == 4'd8 && wd[1]) pos[wch] <= 40'd0;
        if (silence || rst) active <= 4'd0;
    end

    always @(posedge clk) begin
        if (rst) begin
            {st, done, mem_req, overrun, dirty} <= 0;
        end else begin
            {done, overrun} <= 2'b00;
            if (busy) dirty <= dirty | {hit_act, hit_pos};
            case (st)
                IDLE: if (start) {st, c, acc_l, acc_r} <= {CHK, 2'd0, 28'sd0, 28'sd0};
                CHK: begin
                    {p, iter} <= {pos[c], 8'd0};
                    dirty <= {hit_act, hit_pos};     // a write now lands after this read
                    st <= (!active[c] || len[c] == 24'd0) ? NEXT : WRAP;
                end
                WRAP: if (looping && {1'b0, p} >= loop_end && iter != 8'd255) {p, iter} <= {p - span, iter + 8'd1};
                    else if (!looping && p >= {len[c], 16'd0}) st <= NEXT;   // mix_stop clears active
                    else {overrun, mem_req, mem_addr, st} <= {iter == 8'd255, 1'b1, base[c] + {8'd0, p[39:16]}, FETCH};
                FETCH: if (mem_ack) {mem_req, s, st} <= {1'b0, mem_data, M1};
                M1: {gl, st} <= {prod[17:0], M2};
                M2: {gr, st} <= {prod[17:0], M3};
                M3: {acc_l, st} <= {acc_l + prod[27:0], M4};
                M4: {acc_r, st} <= {acc_r + prod[27:0], NEXT};   // mix_wb: pos += STEP
                NEXT: {c, st, done} <= (c == 2'd3) ? {2'd0, IDLE, 1'b1} : {c + 2'd1, CHK, 1'b0};
                default: st <= IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
