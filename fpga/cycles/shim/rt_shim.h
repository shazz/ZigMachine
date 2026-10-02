/* Force-included (-include) into every object of the bare-metal rv32 build, so
 * the STOCK wasm2c runtime (wasm-rt-impl.c, wasm-rt-mem-impl.c, ...) compiles
 * against picolibc unchanged. See ../README.md, "The runtime shim".
 *
 * wasm-rt.h saves and restores trap context with sigsetjmp/siglongjmp. There
 * are no signals on a bare core, so the signal mask they would save is empty
 * and plain setjmp/longjmp do the same job. picolibc has both. */
#if !defined(ZM_RT_SHIM_H) && !defined(__ASSEMBLER__) /* trap.S gets -include too */
#define ZM_RT_SHIM_H

#include <setjmp.h>

#define sigjmp_buf jmp_buf
#define sigsetjmp(buf, savemask) setjmp(buf)
#define siglongjmp(buf, val) longjmp(buf, val)

#endif
