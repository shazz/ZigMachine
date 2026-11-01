// The read port shared by the pixel unit and an aux requester (zm_blit_tfetch: AFFINE's span
// list, MAP's map). The port answers in request order with no back-pressure, so each request
// taken leaves its requester's bit in a FIFO and each answer goes to the bit at its head.
// The aux side wins a clock both ask (it is rare and keeps the texture walk fed); neither can
// starve the other for long: the pixel unit has at most 2^5 reads in flight, the aux side 32.
// 64 bits deep: every read that can be in flight at once.
`default_nettype none

module zm_blit_rdmux (
    input  wire        clk,
    input  wire        rst,
    input  wire        px_valid,
    output wire        px_ready,
    input  wire [31:0] px_addr,
    output wire        px_rsp,
    input  wire        aux_valid,
    output wire        aux_ready,
    input  wire [22:0] aux_addr,
    output wire        aux_rsp,
    output wire        rd_req_valid,
    input  wire        rd_req_ready,
    output wire [31:0] rd_req_addr,
    input  wire        rd_rsp_valid
);
    assign rd_req_valid = px_valid || aux_valid;
    assign rd_req_addr = aux_valid ? {9'd0, aux_addr} : px_addr;
    assign aux_ready = rd_req_ready;
    assign px_ready = rd_req_ready && !aux_valid;
    reg who [0:63];                              // 1: the aux side asked
    reg [5:0] wp, rp;
    wire take = rd_req_valid && rd_req_ready;
    always @(posedge clk) if (take) who[wp] <= aux_valid;
    always @(posedge clk) begin
        if (rst) begin wp <= 6'd0; rp <= 6'd0; end
        else begin
            if (take) wp <= wp + 6'd1;
            if (rd_rsp_valid) rp <= rp + 6'd1;
        end
    end
    assign aux_rsp = rd_rsp_valid && who[rp];
    assign px_rsp = rd_rsp_valid && !who[rp];
endmodule
