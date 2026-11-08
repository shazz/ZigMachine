# The key matrix is computed on a $DC01 read now (lazy, libcRSID__C64__MEM.c.sed), and this delay (a modifier the
# PC adds, Shift for F8 / Up / Insert..., seen by the C64 before its key) counted calls: 6 instructions upstream,
# 6 keyboard reads (about 6 frames, longer than a short press) here. 2 reads keeps "the modifier first".
s|^#define SHIFTED_KEY_DELAY 6|#define SHIFTED_KEY_DELAY 2 /* kestrel: counts $DC01 reads, patches/host__keyboard.h.sed */|
