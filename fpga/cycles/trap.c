/* Traps on the cart CPU. The `standard` VexRiscv traps on a misaligned lw/lh/
 * sw/sh (mcause 4 and 6), as most small RISC-V cores do. The ALIGNED build lets
 * the compiler use word loads for wasm memory, so a wasm access that really is
 * misaligned lands here and is emulated byte by byte, as an SBI would do on the
 * board. It is counted, so the report shows how rare it is and its cost is in
 * the cycles. A ZM-X instruction (custom-0) on a core without ZM-X traps as illegal
 * (mcause 2) and runs its C twin here instead (zmx_twin.h, the same integers), counted:
 * a cart built with ZM-X stays right on an older bitstream, only slower (~200 cycles an
 * op, as a misaligned access). Anything else is fatal and reported. */
#include <stdio.h>

#include "board.h"
#include "trap.h"
#include "zmx_twin.h"

uint32_t zm_misaligned[2]; /* [0] loads, [1] stores */
uint32_t zm_zmx_emulated;  /* ZM-X ops the core lacked, run as their twin */

/* -march=rv32im keeps picolibc's rv32im multilib; the CSR ops opt in locally. */
#define ZICSR(insn) ".option push\n.option arch, +zicsr\n" insn "\n.option pop"
#define CSRR(name) ({ uint32_t v_; __asm__ volatile(ZICSR("csrr %0, " #name) : "=r"(v_)); v_; })

static int32_t sext(uint32_t v, int bits) { return (int32_t)(v << (32 - bits)) >> (32 - bits); }

static int emulate_load(uint32_t* r, uint32_t insn) {
    uint32_t f3 = (insn >> 12) & 7, rd = (insn >> 7) & 31;
    const uint8_t* p = (const uint8_t*)(r[(insn >> 15) & 31] + (uint32_t)sext(insn >> 20, 12));
    int n = 1 << (f3 & 3);
    if ((insn & 0x7f) != 0x03 || n == 1 || f3 == 3 || f3 > 5) return 0;
    uint32_t v = 0;
    for (int i = 0; i < n; i++) v |= (uint32_t)p[i] << (8 * i);
    if (f3 == 1) v = (uint32_t)sext(v, 16); /* lh; lhu (5) stays zero-extended */
    if (rd) r[rd] = v;
    zm_misaligned[0]++;
    return 1;
}

static int emulate_store(uint32_t* r, uint32_t insn) {
    uint32_t f3 = (insn >> 12) & 7, imm = ((insn >> 25) << 5) | ((insn >> 7) & 31);
    uint8_t* p = (uint8_t*)(r[(insn >> 15) & 31] + (uint32_t)sext(imm, 12));
    uint32_t v = r[(insn >> 20) & 31];
    if ((insn & 0x7f) != 0x23 || (f3 != 1 && f3 != 2)) return 0;
    for (int i = 0; i < (1 << f3); i++) p[i] = (uint8_t)(v >> (8 * i));
    zm_misaligned[1]++;
    return 1;
}

static int emulate_zmx(uint32_t* r, uint32_t insn) {
    uint32_t rd = (insn >> 7) & 31, v;
    if (!zmx_eval(insn, r[(insn >> 15) & 31], r[(insn >> 20) & 31], &v)) return 0;
    if (rd) r[rd] = v;
    zm_zmx_emulated++;
    return 1;
}

/* 1 when the core runs ZM-X itself (the bitstream has it), 0 when the trap above stands in. */
int zm_zmx_probe(void) {
    uint32_t before = zm_zmx_emulated, a = 0x01010101u, r;
    __asm__ volatile(".insn r CUSTOM_0, 0, 6, %0, %1, %1" : "=r"(r) : "r"(a)); /* zm.add8 */
    return r == 0x02020202u && zm_zmx_emulated == before;
}

void zm_trap(uint32_t* regs) {
    uint32_t cause = CSRR(mcause), epc = CSRR(mepc);
    uint32_t insn = *(const uint32_t*)epc; /* no C extension: every insn is aligned */
    int ok = (cause == 4 && emulate_load(regs, insn)) || (cause == 6 && emulate_store(regs, insn)) ||
             (cause == 2 && emulate_zmx(regs, insn));
    if (ok) {
        __asm__ volatile(ZICSR("csrw mepc, %0") ::"r"(epc + 4));
        return;
    }
    printf("ZM TRAP mcause=%lu mepc=%08lx mtval=%08lx insn=%08lx\n", (unsigned long)cause,
           (unsigned long)epc, (unsigned long)CSRR(mtval), (unsigned long)insn);
    board_finish(3);
}

void trap_install(void) {
    extern void zm_trap_entry(void);
    __asm__ volatile(ZICSR("csrw mtvec, %0") ::"r"(zm_trap_entry));
#ifdef __riscv_flen
    /* mstatus.FS = Initial: an F instruction traps as illegal while it is Off (VexRiscv FpuPlugin). */
    __asm__ volatile(ZICSR("csrs mstatus, %0") ::"r"(1u << 13));
#endif
}
