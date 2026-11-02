# KESTREL: cap the resident pattern / sequence tables (kestrel_port.h) to fit the 2 MiB cart window.
s/^#define NUM_PATTERNS 4096$/#define NUM_PATTERNS KESTREL_MAX_PATTERNS/
s/^#define NUM_SEQUENCES 2048$/#define NUM_SEQUENCES KESTREL_MAX_SEQUENCES/
