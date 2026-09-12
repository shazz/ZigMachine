// Freestanding stand-in for <setjmp.h>. m68kcpu.h includes it unconditionally
// but only USES it for address-error emulation (M68K_EMULATE_ADDRESS_ERROR),
// which is off for us — the 68000 in an SNDH replay never takes one. Declared,
// never defined: a real call fails at link time rather than corrupting a stack
// that wasm would not let us unwind anyway.
#ifndef ZM_FREESTANDING_SETJMP_H
#define ZM_FREESTANDING_SETJMP_H

typedef unsigned long jmp_buf[32];

extern int setjmp(jmp_buf env);
extern void longjmp(jmp_buf env, int val);

#endif
