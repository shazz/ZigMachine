// The seal (rtl/seal/README.md): may this access go out? One decision per
// access, combinational, inside the core's memory-translation slot
// (vexgen/.../ZmSealPlugin.scala), so a "no" is a precise access-fault trap
// (mcause 1 fetch, 5 load, 7 store) and the access never reaches the bus.
//
// - U (user = 1, cart and ROM code): only the windows of zm_seal_map.vh, with
//   their own permissions. Code is execute-only; nothing is both W and X.
// - M (the firmware): everything, except executing from a window the cart can
//   write, so a firmware jump through a cart-made pointer cannot run cart data.
`include "zm_seal_map.vh"

module zm_seal (
    input  wire [31:0] addr,
    input  wire        user,
    output wire        r,
    output wire        w,
    output wire        x
);
    // In a window of 2^lg bytes at base: the bits above lg are base's.
    function automatic hit(input [31:0] a, input [31:0] base, input integer lg);
        hit = (a >> lg) == (base >> lg);
    endfunction

    wire code   = hit(addr, `ZS_CODE_BASE, `ZS_CODE_LOG2);
    wire rodata = hit(addr, `ZS_RODATA_BASE, `ZS_RODATA_LOG2);
    wire data   = hit(addr, `ZS_DATA_BASE, `ZS_DATA_LOG2);
    wire linear = hit(addr, `ZS_LINEAR_BASE, `ZS_LINEAR_LOG2);
    wire video  = hit(addr, `ZS_VIDEO_BASE, `ZS_VIDEO_LOG2);

    wire u_w = data | linear | video;
    wire u_r = rodata | u_w;
    wire u_x = code;

    assign r = user ? u_r : 1'b1;
    assign w = user ? u_w : 1'b1;
    assign x = user ? u_x : ~u_w;
endmodule
