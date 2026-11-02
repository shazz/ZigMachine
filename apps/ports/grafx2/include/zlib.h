/* zlib shim for GrafX2 v1: only the C64 GPX loader inflates; it reports a data error instead. */
#ifndef KESTREL_ZLIB_SHIM_H
#define KESTREL_ZLIB_SHIM_H
typedef unsigned long uLongf;
typedef unsigned long uLong;
typedef unsigned char Bytef;
#define Z_OK 0
#define Z_DATA_ERROR (-3)
#define Z_MEM_ERROR (-4)
#define Z_BUF_ERROR (-5)
static inline int uncompress(Bytef *d, uLongf *dl, const Bytef *s, uLong sl) { (void)d; (void)dl; (void)s; (void)sl; return Z_DATA_ERROR; }
static inline const char *zError(int e) { (void)e; return "no zlib on KESTREL"; }
#endif
