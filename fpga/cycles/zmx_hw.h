/* ZM-X v1 as instructions (fpga/review/KESTREL_NEXT_ISA.md section 5): a cart's env.zm*
 * imports, compiled to the custom-0 ops when the image is built with ZM_ZMX (zm_variant.h
 * maps each w2c_env_zm* call here). Non-volatile asm with no memory clobber: GCC may CSE,
 * hoist and schedule an op like any ALU instruction. The browser and the native host run
 * rom.wasm's twins (rom/zmx_exports.zig over libs/zig/zmx.zig) for the same imports; a
 * bitstream without ZM-X traps each op as illegal and trap.c runs zmx_twin.h's instead
 * (bmain.c prints "ZM ZMX 0" at boot then). tests/test_zmx.py pins the encodings. */
#ifndef ZM_ZMX_HW_H
#define ZM_ZMX_HW_H

#include <stdint.h>

#define ZMX_OP(f3, f7, a, b)                                                                            \
    ({                                                                                                  \
        uint32_t r_;                                                                                    \
        __asm__(".insn r CUSTOM_0, %3, %4, %0, %1, %2" : "=r"(r_) : "r"(a), "r"(b), "i"(f3), "i"(f7)); \
        r_;                                                                                             \
    })

/* tex2d's dims are an immediate: a constant (the usual case, folded to one instruction once
 * inlined) or any run-time value through this 64-way switch. */
static inline __attribute__((always_inline)) uint32_t zmx_hw_tex2d(uint32_t u, uint32_t v, uint32_t d) {
    switch (d & 63u) {
#define ZMX_T(n) \
    case n: return ZMX_OP(7, n, u, v);
#define ZMX_T8(h) ZMX_T(h * 8 + 0) ZMX_T(h * 8 + 1) ZMX_T(h * 8 + 2) ZMX_T(h * 8 + 3) \
    ZMX_T(h * 8 + 4) ZMX_T(h * 8 + 5) ZMX_T(h * 8 + 6) ZMX_T(h * 8 + 7)
        ZMX_T8(0) ZMX_T8(1) ZMX_T8(2) ZMX_T8(3) ZMX_T8(4) ZMX_T8(5) ZMX_T8(6) default: ZMX_T8(7)
#undef ZMX_T8
#undef ZMX_T
    }
}

#define w2c_env_zmMulsh16(e, a, b) ZMX_OP(0, 1, a, b)
#define w2c_env_zmMulsh15(e, a, b) ZMX_OP(1, 1, a, b)
#define w2c_env_zmFunnel1(e, a, b) ZMX_OP(1, 2, a, b)
#define w2c_env_zmFunnel2(e, a, b) ZMX_OP(2, 2, a, b)
#define w2c_env_zmFunnel3(e, a, b) ZMX_OP(3, 2, a, b)
#define w2c_env_zmAdd8s(e, a, b) ZMX_OP(0, 3, a, b)
#define w2c_env_zmSub8s(e, a, b) ZMX_OP(0, 4, a, b)
#define w2c_env_zmAvg8(e, a, b) ZMX_OP(0, 5, a, b)
#define w2c_env_zmAdd8(e, a, b) ZMX_OP(0, 6, a, b)
#define w2c_env_zmTex2d(e, u, v, d) zmx_hw_tex2d(u, v, d)

#endif
