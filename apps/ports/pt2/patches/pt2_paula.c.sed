# KESTREL: Paula reads the null buffer for up to one sample length (upstream sizes it for the largest
# sample, 0xFFFF words); samples are capped at 13312 bytes (pt2_config.c.sed), so 32 KB (kept from the 4 MiB cap) covers them.
s/^static int8_t nullSample\[0xFFFF\*2\];/static int8_t nullSample[0x4000*2]; \/* KESTREL *\//
