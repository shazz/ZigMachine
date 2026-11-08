# Code size is what costs on ZIGGY (a 16 KB I$; apps/perf/cost_model.mjs): forced inlining copied the memory
# accessors into every opcode (a 91 KB emulate function). The compiler decides instead (README.md, "Cost").
s|^#define INLINE  inline  __attribute__((__always_inline__)).*|#define INLINE  inline  /* kestrel: not forced (patches/libcRSID__Optimize.h.sed) */|
