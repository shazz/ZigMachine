# KESTREL: allocate a bus's reverb delay line / chorus buffers when its flags first enable them (cydrvb.c.sed,
# cydchr.c.sed); if the heap cannot hold them the effect stays off on that bus, and the console says so.
/^\tfx->flags = ser->flags;$/a\
\tif ((fx->flags & CYDFX_ENABLE_REVERB) && !fx->rvb.buffer)\
\t{\
\t\tfx->rvb.buffer = calloc(sizeof(*fx->rvb.buffer) * 2, fx->rvb.size);\
\t\tif (!fx->rvb.buffer) { fx->flags &= ~CYDFX_ENABLE_REVERB; kestrel_log("klystron: no memory for a reverb, left off"); }\
\t}\
\tif ((fx->flags & CYDFX_ENABLE_CHORUS) && !fx->chr.lut)\
\t{\
\t\tfx->chr.buffer = calloc(fx->chr.buf_size, sizeof(fx->chr.buffer[0]) * 2);\
\t\tfx->chr.lut = calloc(fx->chr.sample_rate * 4 * CYD_CHORUS_OVERSAMPLE, sizeof(fx->chr.buffer[0]));\
\t\tif (!fx->chr.buffer || !fx->chr.lut) { free(fx->chr.buffer); free(fx->chr.lut); fx->chr.buffer = fx->chr.lut = NULL; fx->flags &= ~CYDFX_ENABLE_CHORUS; kestrel_log("klystron: no memory for a chorus, left off"); }\
\t\telse { fx->chr.lut_size = 0; fx->chr.min_delay = fx->chr.max_delay = -1; }\
\t}
s/^\tcydchr_set(&fx->chr, ser->chr.rate, ser->chr.min_delay, ser->chr.max_delay, ser->chr.sep);$/\tif (fx->chr.lut) cydchr_set(\&fx->chr, ser->chr.rate, ser->chr.min_delay, ser->chr.max_delay, ser->chr.sep);/
