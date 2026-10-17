/* The sound core multiplies in hardware but has no divider (vexgen `nodiv`), so its firmware is
 * built -march=rv32i_zmmul (cycles/sound.mk SND_ARCH) and links the rv32i multilib: the rv32im
 * one's libgcc divides with DIV/REM, which the core traps. That libgcc's soft-float and 64-bit
 * routines (__mulsf3, __udivdi3...) multiply through __mulsi3 / __muldi3, a shift-and-add loop
 * there: these two, linked ahead of it, are the core's MUL / MULHU instead. */
#include <stdint.h>

uint32_t __mulsi3(uint32_t a, uint32_t b);
uint64_t __muldi3(uint64_t a, uint64_t b);

uint32_t __mulsi3(uint32_t a, uint32_t b) { return a * b; }

uint64_t __muldi3(uint64_t a, uint64_t b) { return a * b; }
