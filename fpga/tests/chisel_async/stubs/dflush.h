/* tests/chisel_async: the whole-cache invalidate, recorded. */
extern int swept;
static inline void zm_dflush(void) { swept = 1; }
